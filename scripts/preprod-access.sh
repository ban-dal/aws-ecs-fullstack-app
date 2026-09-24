#!/usr/bin/env bash
# preprod 단일 호스트의 WireGuard peer를 SSM으로 등록한다. 개인 키는 로컬 기기에만
# 저장하고, Terraform·GitHub·SSM 명령에는 공개 키만 보낸다. AWS_PROFILE에는 MFA로
# 수임한 운영 역할의 Terraform용 프로필을 지정한다.
set -euo pipefail
umask 077

command="${1:-}"
region="${AWS_REGION:-ap-northeast-2}"
name="aws-fullstack-lab-preprod"
config_dir="${HOME}/.config/aws-fullstack-lab/preprod"
private_key="$config_dir/client.key"
public_key="$config_dir/client.pub"
client_config="$config_dir/preprod.conf"

if [[ "$command" != enroll && "$command" != revoke && "$command" != check && "$command" != stop && "$command" != start ]]; then
  echo "usage: AWS_PROFILE=aws-fullstack-operator-terraform scripts/preprod-access.sh enroll|revoke|check|stop|start" >&2
  exit 2
fi

if [[ -z "${AWS_PROFILE:-}" ]]; then
  echo "AWS_PROFILE에 MFA 운영 역할 프로필을 지정하세요." >&2
  exit 1
fi

caller="$(aws sts get-caller-identity --region "$region" --query Arn --output text)"
if [[ "$caller" != *":assumed-role/aws-fullstack-lab-bootstrap-operator/"* ]]; then
  echo "MFA 운영 역할이 아닙니다. docs/operations.md의 로컬 인증 절차를 확인하세요." >&2
  exit 1
fi

if [[ "$command" == check ]]; then
  aws ecs describe-services --region "$region" --cluster "$name-cluster" --services web \
    --query 'services[0].[desiredCount,runningCount,deployments[0].rolloutState]' --output text
  curl --fail --silent --show-error --max-time 5 http://10.62.0.1:3000/api/health
  echo
  exit 0
fi

if [[ "$command" == stop ]]; then
  aws ecs update-service --region "$region" --cluster "$name-cluster" --service web \
    --desired-count 0 --query 'service.desiredCount' --output text >/dev/null
  aws ecs wait services-stable --region "$region" --cluster "$name-cluster" --services web
  aws autoscaling update-auto-scaling-group --region "$region" --auto-scaling-group-name "$name-ecs" \
    --min-size 0 --desired-capacity 0
  echo "preprod 태스크와 호스트를 0대로 줄였습니다. EBS도 호스트 종료와 함께 삭제됩니다."
  echo "다음 Terraform apply는 선언값 1대로 다시 올리므로 plan을 확인하세요."
  exit 0
fi

if [[ "$command" == start ]]; then
  aws autoscaling update-auto-scaling-group --region "$region" --auto-scaling-group-name "$name-ecs" \
    --min-size 1 --desired-capacity 1
  aws ecs update-service --region "$region" --cluster "$name-cluster" --service web \
    --desired-count 1 --query 'service.desiredCount' --output text >/dev/null
  echo "preprod를 1대로 시작했습니다. 호스트가 등록되면 enroll로 VPN peer를 다시 등록하세요."
  exit 0
fi

instance_id="$(aws autoscaling describe-auto-scaling-groups --region "$region" \
  --auto-scaling-group-names "$name-ecs" \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)"
if [[ -z "$instance_id" || "$instance_id" == None ]]; then
  echo "preprod ECS 호스트가 아직 없습니다. apply 완료와 Auto Scaling 상태를 확인하세요." >&2
  exit 1
fi

send_command() {
  local shell_command="$1"
  local parameters_file command_id
  parameters_file="$(mktemp)"
  jq -n --arg command "$shell_command" '{commands:[$command]}' > "$parameters_file"
  if ! command_id="$(aws ssm send-command --region "$region" --instance-ids "$instance_id" \
    --document-name AWS-RunShellScript --parameters "file://$parameters_file" \
    --query 'Command.CommandId' --output text)"; then
    rm -f "$parameters_file"
    return 1
  fi
  rm -f "$parameters_file"
  aws ssm wait command-executed --region "$region" --command-id "$command_id" --instance-id "$instance_id"
  aws ssm get-command-invocation --region "$region" --command-id "$command_id" \
    --instance-id "$instance_id" --query 'StandardOutputContent' --output text
}

if [[ "$command" == enroll ]]; then
  command -v wg >/dev/null || { echo "로컬에 wireguard-tools의 wg 명령이 필요합니다." >&2; exit 1; }
  mkdir -p "$config_dir"
  if [[ ! -f "$private_key" ]]; then
    wg genkey > "$private_key"
    wg pubkey < "$private_key" > "$public_key"
  fi
  client_public="$(cat "$public_key")"
  [[ "$client_public" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { echo "클라이언트 공개 키 형식이 잘못되었습니다." >&2; exit 1; }

  server_public="$(send_command 'cat /etc/wireguard/server.pub' | tr -d '\r\n')"
  [[ "$server_public" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { echo "서버 공개 키를 읽지 못했습니다. 호스트 초기화를 확인하세요." >&2; exit 1; }
  send_command "wg set wg0 peer $client_public allowed-ips 10.62.0.2/32 && wg-quick save wg0" >/dev/null

  endpoint_ip="$(aws ec2 describe-instances --region "$region" --instance-ids "$instance_id" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
  [[ "$endpoint_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "호스트의 공개 IP를 읽지 못했습니다." >&2; exit 1; }
  cat > "$client_config" <<EOF
[Interface]
PrivateKey = $(cat "$private_key")
Address = 10.62.0.2/32

[Peer]
PublicKey = $server_public
Endpoint = $endpoint_ip:51820
AllowedIPs = 10.62.0.1/32
PersistentKeepalive = 25
EOF
  chmod 0600 "$client_config"
  echo "VPN 설정: $client_config"
  echo "WireGuard 앱에서 이 파일을 가져와 연결한 뒤 scripts/preprod-access.sh check를 실행하세요."
  echo "앱 주소: http://10.62.0.1:3000"
  exit 0
fi

if [[ ! -f "$public_key" ]]; then
  echo "등록한 클라이언트 공개 키가 없습니다." >&2
  exit 1
fi
client_public="$(cat "$public_key")"
[[ "$client_public" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { echo "클라이언트 공개 키 형식이 잘못되었습니다." >&2; exit 1; }
send_command "wg set wg0 peer $client_public remove && wg-quick save wg0" >/dev/null
echo "호스트에서 클라이언트 peer를 제거했습니다. 로컬 설정은 수동으로 삭제하세요: $config_dir"

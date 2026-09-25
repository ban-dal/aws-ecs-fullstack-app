#!/usr/bin/env bash
# AWS Client VPN의 로컬 CA·기기 인증서를 만들고, 서버 인증서만 ACM에 등록한다.
# 개인 키와 클라이언트 .ovpn은 이 Mac의 사용자 설정 디렉터리에만 둔다.
# prepare는 GitHub plan/apply가 사용할 ACM ARN을 repository secret으로 설정한다.
# suspend는 preprod 태스크·호스트를 0대로 줄이고 VPN 대상 서브넷 연결을 해제한다.
# 다시 쓸 때는 preprod 적용 workflow가 선언값대로 모두 되돌린다.
set -euo pipefail
umask 077

command="${1:-}"
region="${AWS_REGION:-ap-northeast-2}"
repo="${GITHUB_REPOSITORY:-ban-dal/aws-ecs-fullstack-app}"
name="aws-fullstack-lab-preprod-client-vpn"
dir="${HOME}/.config/aws-fullstack-lab/preprod/client-vpn"
arn_file="$dir/server-certificate-arn"
config_file="$dir/preprod.ovpn"

if [[ "$command" != prepare && "$command" != config && "$command" != check && "$command" != suspend ]]; then
  echo "usage: AWS_PROFILE=aws-fullstack-operator-terraform scripts/preprod-client-vpn.sh prepare|config|check|suspend" >&2
  exit 2
fi
[[ -n "${AWS_PROFILE:-}" ]] || { echo "AWS_PROFILE에 MFA 운영 역할 프로필을 지정하세요." >&2; exit 1; }
caller="$(aws sts get-caller-identity --region "$region" --query Arn --output text)"
[[ "$caller" == *":assumed-role/aws-fullstack-lab-bootstrap-operator/"* ]] || {
  echo "MFA 운영 역할이 아닙니다. docs/operations.md의 로컬 인증 절차를 확인하세요." >&2
  exit 1
}

if [[ "$command" == prepare ]]; then
  command -v openssl >/dev/null || { echo "openssl 명령이 필요합니다." >&2; exit 1; }
  command -v gh >/dev/null || { echo "GitHub CLI gh 명령이 필요합니다." >&2; exit 1; }
  mkdir -p "$dir"
  if [[ ! -f "$dir/ca.key" ]]; then
    openssl genrsa -out "$dir/ca.key" 2048 >/dev/null 2>&1
    openssl req -new -x509 -sha256 -days 3650 -key "$dir/ca.key" -out "$dir/ca.crt" \
      -subj "/CN=aws-fullstack-lab-preprod-client-vpn-ca" \
      -addext 'basicConstraints=critical,CA:TRUE' \
      -addext 'keyUsage=critical,keyCertSign,cRLSign' >/dev/null 2>&1
  fi
  if [[ ! -f "$dir/server.key" ]]; then
    openssl genrsa -out "$dir/server.key" 2048 >/dev/null 2>&1
    openssl req -new -key "$dir/server.key" -out "$dir/server.csr" \
      -subj '/CN=server' >/dev/null 2>&1
    printf 'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:server\n' > "$dir/server.ext"
    openssl x509 -req -in "$dir/server.csr" -CA "$dir/ca.crt" -CAkey "$dir/ca.key" \
      -CAcreateserial -out "$dir/server.crt" -days 825 -sha256 \
      -extfile "$dir/server.ext" >/dev/null 2>&1
  fi
  if [[ ! -f "$dir/client.key" ]]; then
    openssl genrsa -out "$dir/client.key" 2048 >/dev/null 2>&1
    openssl req -new -key "$dir/client.key" -out "$dir/client.csr" \
      -subj '/CN=bandal-preprod-mac' >/dev/null 2>&1
    printf 'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=clientAuth\n' > "$dir/client.ext"
    openssl x509 -req -in "$dir/client.csr" -CA "$dir/ca.crt" -CAkey "$dir/ca.key" \
      -CAcreateserial -out "$dir/client.crt" -days 825 -sha256 \
      -extfile "$dir/client.ext" >/dev/null 2>&1
  fi
  openssl verify -CAfile "$dir/ca.crt" "$dir/server.crt" "$dir/client.crt" >/dev/null
  if [[ ! -f "$arn_file" ]]; then
    temporary_arn="$(mktemp "$dir/server-certificate-arn.XXXXXX")"
    aws acm import-certificate --region "$region" \
      --certificate "fileb://$dir/server.crt" \
      --private-key "fileb://$dir/server.key" \
      --certificate-chain "fileb://$dir/ca.crt" \
      --query CertificateArn --output text > "$temporary_arn"
    [[ -s "$temporary_arn" ]] || { rm -f "$temporary_arn"; echo "ACM 인증서 ARN을 받지 못했습니다." >&2; exit 1; }
    mv "$temporary_arn" "$arn_file"
    aws acm add-tags-to-certificate --region "$region" --certificate-arn "$(cat "$arn_file")" \
      --tags Key=Project,Value=aws-fullstack-lab Key=Environment,Value=preprod Key=ManagedBy,Value=script
  fi
  gh secret set CLIENT_VPN_SERVER_CERTIFICATE_ARN --repo "$repo" < "$arn_file"
  echo "서버 인증서를 ACM에 등록하고 GitHub secret을 설정했습니다."
  echo "CA와 클라이언트 개인 키는 $dir 에만 보관합니다."
  exit 0
fi

endpoint_id="$(aws ec2 describe-client-vpn-endpoints --region "$region" \
  --filters "Name=tag:Name,Values=$name" \
  --query 'ClientVpnEndpoints[0].ClientVpnEndpointId' --output text)"
[[ -n "$endpoint_id" && "$endpoint_id" != None ]] || {
  echo "preprod Client VPN 엔드포인트가 없습니다. 적용 workflow를 확인하세요." >&2
  exit 1
}

if [[ "$command" == config ]]; then
  [[ -f "$dir/client.crt" && -f "$dir/client.key" ]] || {
    echo "로컬 클라이언트 인증서가 없습니다. prepare를 먼저 실행하세요." >&2
    exit 1
  }
  aws ec2 export-client-vpn-client-configuration --region "$region" \
    --client-vpn-endpoint-id "$endpoint_id" --query ClientConfiguration --output text > "$config_file"
  {
    printf '\n<cert>\n'
    cat "$dir/client.crt"
    printf '</cert>\n<key>\n'
    cat "$dir/client.key"
    printf '</key>\n'
  } >> "$config_file"
  chmod 0600 "$config_file"
  echo "AWS VPN Client에 가져올 설정: $config_file"
  echo "이 파일에는 개인 키가 있으므로 저장소나 메시지에 올리지 마세요."
  exit 0
fi

if [[ "$command" == suspend ]]; then
  aws ecs update-service --region "$region" --cluster aws-fullstack-lab-preprod-cluster --service web \
    --desired-count 0 --query 'service.desiredCount' --output text >/dev/null
  aws ecs wait services-stable --region "$region" --cluster aws-fullstack-lab-preprod-cluster --services web
  aws autoscaling update-auto-scaling-group --region "$region" --auto-scaling-group-name aws-fullstack-lab-preprod-ecs \
    --min-size 0 --desired-capacity 0
  echo "preprod 태스크와 호스트를 0대로 줄였습니다. EBS와 공개 IP는 호스트 종료와 함께 해제됩니다."
  association_id="$(aws ec2 describe-client-vpn-target-networks --region "$region" \
    --client-vpn-endpoint-id "$endpoint_id" \
    --query 'ClientVpnTargetNetworks[0].AssociationId' --output text)"
  if [[ -z "$association_id" || "$association_id" == None ]]; then
    echo "연결된 대상 서브넷이 없습니다."
  else
    aws ec2 disassociate-client-vpn-target-network --region "$region" \
      --client-vpn-endpoint-id "$endpoint_id" --association-id "$association_id" >/dev/null
    echo "대상 서브넷 연결 해제를 시작했습니다. 완료되면 VPN 접속과 엔드포인트 연결 시간 과금이 멈춥니다."
  fi
  echo "다시 쓸 때는 preprod 적용 workflow의 새 plan에서 서브넷 연결·호스트·태스크 복구를 확인하고 적용하세요."
  exit 0
fi

instance_id="$(aws autoscaling describe-auto-scaling-groups --region "$region" \
  --auto-scaling-group-names aws-fullstack-lab-preprod-ecs \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)"
[[ -n "$instance_id" && "$instance_id" != None ]] || { echo "preprod ECS 호스트가 없습니다." >&2; exit 1; }
private_ip="$(aws ec2 describe-instances --region "$region" --instance-ids "$instance_id" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)"
[[ "$private_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "호스트의 사설 IP를 읽지 못했습니다." >&2; exit 1; }
aws ecs describe-services --region "$region" --cluster aws-fullstack-lab-preprod-cluster --services web \
  --query 'services[0].[desiredCount,runningCount,deployments[0].rolloutState]' --output text
curl --fail --silent --show-error --max-time 5 "http://$private_ip:3000/api/health"
echo
echo "앱 주소: http://$private_ip:3000"

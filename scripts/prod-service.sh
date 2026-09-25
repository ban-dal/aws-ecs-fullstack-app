#!/usr/bin/env bash
# prod 공개 서비스 확인과 비용 중지. suspend는 태스크·호스트를 0대로 줄이고 ALB를
# 삭제한다. 다음 prod 적용 workflow가 Terraform 차이를 확인하고 복구한다.
set -euo pipefail

command="${1:-}"
region="${AWS_REGION:-ap-northeast-2}"
cluster="aws-fullstack-lab-prod-cluster"
autoscaling_group="aws-fullstack-lab-prod-ecs"
load_balancer="aws-fullstack-lab-prod-web"
target_group="aws-fullstack-lab-prod-web"

[[ "$command" == check || "$command" == suspend ]] || {
  echo "usage: scripts/prod-service.sh check|suspend" >&2
  exit 2
}

aws sts get-caller-identity >/dev/null

if [[ "$command" == check ]]; then
  service="$(aws ecs describe-services --region "$region" --cluster "$cluster" --services web \
    --query 'services[0].[desiredCount,runningCount,deployments[0].rolloutState]' --output text)"
  [[ "$service" == $'2\t2\tCOMPLETED' ]] || {
    echo "prod ECS 서비스가 정상 상태가 아니다: $service" >&2
    exit 1
  }

  arn="$(aws elbv2 describe-target-groups --region "$region" --names "$target_group" \
    --query 'TargetGroups[0].TargetGroupArn' --output text)"
  healthy="$(aws elbv2 describe-target-health --region "$region" --target-group-arn "$arn" \
    --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' --output text)"
  [[ "$healthy" == 2 ]] || {
    echo "prod ALB의 정상 대상이 2개가 아니다: $healthy" >&2
    exit 1
  }

  curl -fsS --max-time 10 https://aws.bandal.dev/api/health \
    | jq -e '.status == "ok" and .environment == "prod"' >/dev/null
  echo "prod 정상: ECS 2/2, ALB 대상 2/2, HTTPS health 응답 확인"
  exit 0
fi

aws ecs update-service --region "$region" --cluster "$cluster" --service web \
  --desired-count 0 >/dev/null
aws ecs wait services-stable --region "$region" --cluster "$cluster" --services web

aws autoscaling update-auto-scaling-group --region "$region" \
  --auto-scaling-group-name "$autoscaling_group" --min-size 0 --desired-capacity 0

for _ in {1..60}; do
  remaining="$(aws autoscaling describe-auto-scaling-groups --region "$region" \
    --auto-scaling-group-names "$autoscaling_group" \
    --query 'length(AutoScalingGroups[0].Instances)' --output text)"
  [[ "$remaining" == 0 ]] && break
  sleep 10
done
[[ "$remaining" == 0 ]] || {
  echo "prod 호스트 종료가 끝나지 않았다: $remaining 대" >&2
  exit 1
}

arn="$(aws elbv2 describe-load-balancers --region "$region" --names "$load_balancer" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || true)"
if [[ -n "$arn" && "$arn" != None ]]; then
  aws elbv2 delete-load-balancer --region "$region" --load-balancer-arn "$arn"
  aws elbv2 wait load-balancers-deleted --region "$region" --load-balancer-arns "$arn"
fi

echo "prod 태스크·호스트를 0대로 줄이고 ALB를 삭제했다. DNS는 재적용 전까지 응답하지 않는다."
echo "완전 종료 여부와 남은 EBS·IPv4·로그 비용은 AWS Billing에서 확인한다."

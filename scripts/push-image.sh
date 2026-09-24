#!/usr/bin/env bash
# 로컬에 빌드한 이미지를 한 환경의 ECR 저장소에 올린다. Build image workflow가 main에서
# 공통 image 역할로 로그인한 뒤 호출한다.
#
#   scripts/push-image.sh <preprod|prod> <local-image>
#
# 저장소는 태그를 덮어쓸 수 없으므로(IMMUTABLE) 같은 태그가 이미 있으면 올리지 않는다.
# workflow를 다시 실행해도 안전하다. 푸시할 때의 취약점 스캔은 레지스트리 설정이 맡고,
# 여기서는 결과 개수만 요약에 남긴다.
set -euo pipefail

environment="${1:?usage: scripts/push-image.sh <preprod|prod> <local-image>}"
local_image="${2:?usage: scripts/push-image.sh <preprod|prod> <local-image>}"
: "${AWS_ACCOUNT_ID:?}" "${AWS_REGION:?}" "${IMAGE_TAG:?}"

registry="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
repository="aws-fullstack-lab-$environment-web"
summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

if aws ecr describe-images --repository-name "$repository" --image-ids "imageTag=$IMAGE_TAG" >/dev/null 2>&1; then
  echo "$repository:$IMAGE_TAG already exists; skipping push"
else
  aws ecr get-login-password | docker login --username AWS --password-stdin "$registry"
  docker tag "$local_image" "$registry/$repository:$IMAGE_TAG"
  docker push "$registry/$repository:$IMAGE_TAG"
fi

digest="$(aws ecr describe-images --repository-name "$repository" --image-ids "imageTag=$IMAGE_TAG" \
  --query 'imageDetails[0].imageDigest' --output text)"

findings="scan pending"
if aws ecr wait image-scan-complete --repository-name "$repository" --image-id "imageTag=$IMAGE_TAG" 2>/dev/null; then
  findings="$(aws ecr describe-image-scan-findings --repository-name "$repository" --image-id "imageTag=$IMAGE_TAG" \
    --query 'imageScanFindings.findingSeverityCounts' --output json | jq -r 'to_entries | map("\(.key)=\(.value)") | join(" ") | if . == "" then "no findings" else . end')"
fi

{
  echo "### $environment"
  echo "- image: \`$repository:$IMAGE_TAG\`"
  echo "- digest: \`$digest\`"
  echo "- scan: $findings"
} >> "$summary"

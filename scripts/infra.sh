#!/usr/bin/env bash
# 로컬 MFA 운영 역할 세션에서 Terraform 루트 하나를 plan하고 apply한다.
#
# 모든 루트를 사람이 적용한다. bootstrap은 IAM 역할 자체를 만들므로 GitHub에 맡기면
# GitHub 쪽에 계정 관리자 권한을 줘야 한다. 환경 루트도 같은 경로로 적용해 적용 절차를
# 하나로 둔다. PR에는 `plan` 요약을 적고, merge 후 main에서 같은 루트를 다시 `plan`해
# PR에 적은 범위와 비교한 뒤 그 저장 plan으로 `apply`한다.
#
#   scripts/infra.sh <bootstrap|preprod|prod> plan    # 모든 브랜치: 저장 plan, 변경 요약, 검사
#   scripts/infra.sh <bootstrap|preprod|prod> apply   # main 전용: `plan`이 만든 저장 plan을 적용
#
# 어떤 변경을 어떤 프로필로 적용하는지는 docs/operations.md에 있다.
set -euo pipefail

target="${1:-}"
command="${2:-}"
usage() { echo "usage: scripts/infra.sh bootstrap|preprod|prod plan|apply" >&2; exit 2; }
[[ "$target" == bootstrap || "$target" == preprod || "$target" == prod ]] || usage

root="$(git rev-parse --show-toplevel)"
if [[ "$target" == bootstrap ]]; then chdir="$root/infra/bootstrap"; else chdir="$root/infra/environments/$target"; fi
tf=(terraform -chdir="$chdir")
work="${TMPDIR:-/tmp}/aws-fullstack-infra/$target"

# 계정 ID와 state 버킷 이름은 저장소에 두지 않는다. Git에서 제외된 bootstrap
# terraform.tfvars에서 읽고, 출력은 PR에 붙여 넣을 수 있도록 계정 ID를 가린다.
tfvar() {
  awk -F'"' -v name="$1" '$1 ~ "^" name "[[:space:]]*=" {print $2}' "$root/infra/bootstrap/terraform.tfvars" 2>/dev/null
}
state_bucket="$(tfvar state_bucket_name)"
[[ -n "$state_bucket" ]] || { echo "state_bucket_name is missing in infra/bootstrap/terraform.tfvars" >&2; exit 1; }
if [[ "$target" == bootstrap ]]; then
  vars=(-var-file=terraform.tfvars)
else
  vars=()
  TF_VAR_expected_account_id="$(tfvar expected_account_id)"
  [[ -n "$TF_VAR_expected_account_id" ]] || { echo "expected_account_id is missing in infra/bootstrap/terraform.tfvars" >&2; exit 1; }
  export TF_VAR_expected_account_id
fi
if [[ "$target" == preprod ]]; then
  # scripts/preprod-client-vpn.sh prepare가 ACM에 등록한 서버 인증서 ARN이다.
  arn_file="$HOME/.config/aws-fullstack-lab/preprod/client-vpn/server-certificate-arn"
  [[ -s "$arn_file" ]] || { echo "Client VPN server certificate ARN is missing; run: scripts/preprod-client-vpn.sh prepare" >&2; exit 1; }
  TF_VAR_client_vpn_server_certificate_arn="$(cat "$arn_file")"
  export TF_VAR_client_vpn_server_certificate_arn
fi

caller() {
  aws sts get-caller-identity --query Arn --output text | sed -E 's/[0-9]{12}/<account-id>/'
}

init() {
  "${tf[@]}" init -reconfigure -input=false -no-color \
    -backend-config="bucket=$state_bucket" \
    -backend-config="key=$target/terraform.tfstate" \
    -backend-config="region=ap-northeast-2" >/dev/null
}

plan() {
  rm -rf "$work"
  mkdir -p -m 700 "$work"
  git -C "$root" rev-parse HEAD > "$work/commit"
  # 커밋하지 않은 코드의 plan은 검토용으로는 괜찮지만 적용해서는 안 된다.
  [[ -z "$(git -C "$root" status --porcelain -- infra scripts)" ]] || touch "$work/dirty"
  echo "caller: $(caller)"
  echo "commit: $(cat "$work/commit")"
  init
  "${tf[@]}" plan -input=false -no-color -lock-timeout=5m ${vars[@]+"${vars[@]}"} -out="$work/tfplan" > "$work/plan.log" 2>&1 \
    || { tail -n 30 "$work/plan.log" >&2; exit 1; }
  "${tf[@]}" show -json "$work/tfplan" > "$work/plan.json"
  echo "$target plan:"
  "$root/scripts/tfplan.sh" summary "$work/plan.json"
  if [[ "$target" == bootstrap ]]; then
    PLAN_JSON="$work/plan.json" node --test --test-reporter=dot "$root"/infra/bootstrap/tests/*.test.mjs
  else
    "$root/scripts/tfplan.sh" check-foundation "$work/plan.json" || { rm -f "$work/tfplan"; exit 1; }
  fi
  echo "saved plan: $work/tfplan (full output: $work/plan.log)"
}

apply() {
  [[ -f "$work/tfplan" ]] || { echo "no saved plan; run: scripts/infra.sh $target plan" >&2; exit 1; }
  [[ "$(git -C "$root" branch --show-current)" == main ]] || { echo "apply runs on main only" >&2; exit 1; }
  git -C "$root" fetch -q origin main
  local head
  head="$(git -C "$root" rev-parse HEAD)"
  [[ "$head" == "$(git -C "$root" rev-parse origin/main)" ]] || { echo "main is not at origin/main" >&2; exit 1; }
  [[ "$head" == "$(cat "$work/commit")" ]] || { echo "saved plan was made from another commit; run plan again" >&2; exit 1; }
  [[ ! -f "$work/dirty" ]] || { echo "saved plan includes uncommitted changes; run plan again" >&2; exit 1; }
  echo "caller: $(caller)"
  echo "commit: $head"
  echo "$target plan:"
  "$root/scripts/tfplan.sh" summary "$work/plan.json"
  init
  "${tf[@]}" apply -input=false -no-color "$work/tfplan" | grep -E '^Apply complete'
  local status=0
  "${tf[@]}" plan -input=false -no-color -lock-timeout=5m -detailed-exitcode ${vars[@]+"${vars[@]}"} >/dev/null || status=$?
  rm -rf "$work"
  echo "post-apply plan exit code: $status (0 = no changes)"
  return "$status"
}

case "$command" in
  plan) plan ;;
  apply) apply ;;
  *) usage ;;
esac

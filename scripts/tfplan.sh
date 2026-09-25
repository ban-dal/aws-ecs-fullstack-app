#!/usr/bin/env bash
# `terraform show -json`으로 만든 plan JSON을 요약·검사한다. bootstrap 스크립트와
# GitHub workflow가 같은 기준을 쓰도록 한곳에 둔다.
#
#   scripts/tfplan.sh summary <plan.json>            # 생성·수정·삭제·교체·state 제외 개수와 대상 목록
#   scripts/tfplan.sh check-foundation <plan.json>   # 적용 workflow가 허용하는 변경인지 검사
#   scripts/tfplan.sh fingerprint <plan.json>        # 변경 내용의 해시
set -euo pipefail

command="${1:-}"
plan_json="${2:-}"
[[ -f "$plan_json" ]] || { echo "usage: scripts/tfplan.sh summary|check-foundation|fingerprint <plan.json>" >&2; exit 2; }

case "$command" in
  summary)
    # 기존 리소스를 state로 가져오는 import와 주소만 바꾸는 move는 no-op이지만, 리뷰에서
    # 보이도록 따로 센다. forget은 removed 블록으로 리소스를 지우지 않고 state에서만 뺀다.
    jq -r '
      def kind:
        if (.change.actions | length) > 1 then "replace"
        elif .change.actions == ["no-op"] and .change.importing then "import"
        elif .change.actions == ["no-op"] and .previous_address then "move"
        else .change.actions[0] end;
      [.resource_changes[]? | select(.change.actions != ["no-op"] or .change.importing or .previous_address)
        | {address, kind: kind, from: .previous_address}] as $changes
      | ([["create", "update", "delete", "replace", "forget", "import", "move"][] as $k
          | "\($k)=\([$changes[] | select(.kind == $k)] | length)"] | join(" ")),
        ($changes[] | "- \(.kind) \(.address)" + (if .from then " (from \(.from))" else "" end))
    ' "$plan_json"
    ;;

  check-foundation)
    # 환경 루트의 모듈 안에서 생기는 생성·수정만 허용한다. 삭제와 교체는 데이터를
    # 잃거나 서비스가 끊길 수 있어 이 workflow로 적용하지 않는다. 필요하면 별도로 검토한
    # 절차를 만든다. 루트에는 모듈 호출만 두므로 모든 리소스 주소는 module.로 시작한다.
    violations="$(jq -r '
      .resource_changes[]?
      | select((.address | startswith("module.") | not)
          or ((.change.actions - ["no-op", "create", "update", "read"]) | length > 0))
      | "- \(.change.actions | join("/")) \(.address)"
    ' "$plan_json")"
    if [[ -n "$violations" ]]; then
      echo "적용 workflow가 허용하지 않는 변경:"
      echo "$violations"
      exit 1
    fi
    echo "적용 workflow 검사 통과: 모듈 안의 생성·수정만 있다."
    ;;

  fingerprint)
    # 승인한 plan과 적용할 plan이 같은지 비교하는 값이다. 실행 시각처럼 매번 달라지는
    # 필드는 빼고, 리소스와 output의 변경 내용만 키 순서를 정렬해 해시한다.
    jq -S -c '{
      resource_changes: [.resource_changes[]? | {address, previous_address, change: (.change | {actions, before, after, after_unknown, importing})}],
      output_changes: (.output_changes // {})
    }' "$plan_json" | shasum -a 256 | cut -d' ' -f1
    ;;

  *)
    echo "usage: scripts/tfplan.sh summary|check-foundation|fingerprint <plan.json>" >&2
    exit 2
    ;;
esac

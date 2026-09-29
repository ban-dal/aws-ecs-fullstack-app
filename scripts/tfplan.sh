#!/usr/bin/env bash
# `terraform show -json`으로 만든 plan JSON을 요약·검사한다. scripts/infra.sh가 쓴다.
#
#   scripts/tfplan.sh summary <plan.json>            # 생성·수정·삭제·교체·state 제외 개수와 대상 목록
#   scripts/tfplan.sh check-foundation <plan.json>   # 환경 루트 적용이 허용하는 변경인지 검사
set -euo pipefail

command="${1:-}"
plan_json="${2:-}"
[[ -f "$plan_json" ]] || { echo "usage: scripts/tfplan.sh summary|check-foundation <plan.json>" >&2; exit 2; }

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
    # 환경 루트의 모듈 안에서 생기는 생성·수정만 허용한다. 유일한 교체 예외는
    # prod 웹 태스크 정의의 컨테이너 정의 변경이다. create_before_destroy로 새
    # revision을 먼저 만들고 ECS 서비스가 전환한 뒤 기존 revision을 해제한다.
    # 루트에는 모듈 호출만 두므로 모든 리소스 주소는 module.로 시작한다.
    violations="$(jq -r '
      def allowed:
        (.change.actions == ["no-op"]
          or .change.actions == ["create"]
          or .change.actions == ["update"]
          or .change.actions == ["read"])
        or (.address == "module.web.aws_ecs_task_definition.web"
            and .change.actions == ["create", "delete"]
            and .change.replace_paths == [["container_definitions"]]);
      .resource_changes[]?
      | select((.address | startswith("module.") | not)
          or (allowed | not))
      | "- \(.change.actions | join("/")) \(.address)"
    ' "$plan_json")"
    if [[ -n "$violations" ]]; then
      echo "환경 루트 적용이 허용하지 않는 변경:"
      echo "$violations"
      exit 1
    fi
    echo "환경 루트 적용 검사 통과: 모듈 안의 생성·수정 또는 prod 웹 태스크 정의의 선생성 교체만 있다."
    ;;

  *)
    echo "usage: scripts/tfplan.sh summary|check-foundation <plan.json>" >&2
    exit 2
    ;;
esac

# 0006. 작업 기록은 PR과 결정 기록으로

- 상태: 채택

## 맥락

PR마다 `docs/tasks/NNN-*.md`를 쓰고, 다음 PR의 첫 변경에서 이전 Task의 완료일과 merge commit을 채웠다. PR #1~#8 동안 Task 문서와 운영 문서는 약 7.6만 자로, Terraform·workflow 코드 약 1,300줄보다 분량이 컸다. PR마다 문서 변경이 코드 변경의 약 60%였다. 같은 사실이 5~9개 파일에 반복됐고, 그중 일부가 코드와 어긋났다. merge 후 운영 결과는 구조상 그 PR에 담을 수 없어 매번 다음 PR로 밀렸다.

## 결정

- PR 하나가 작업 하나다. 목표·변경·검증·비용·남은 사항은 PR 본문([템플릿](../../.github/pull_request_template.md))에 쓴다.
- merge 후 운영 작업(bootstrap 적용, GitHub 설정 변경, workflow 실행 결과)은 해당 PR에 댓글로 남긴다. 상태·완료일·merge commit은 GitHub가 기준이며 파일에 다시 쓰지 않는다.
- 코드로 알 수 없는 결정과 이유만 이 디렉터리에 짧게 남긴다.
- 현재 상태는 README 한 곳에 두고 다른 문서는 링크한다. 운영 문서에는 지금 유효한 절차만 둔다.
- `docs/tasks/`는 삭제한다. 이전 기록은 [`a3eb46f`의 docs/tasks](https://github.com/ban-dal/aws-ecs-fullstack-app/tree/a3eb46f/docs/tasks)에서 볼 수 있다.

## 결과와 제약

실행 증거를 보려면 저장소가 아니라 PR을 찾아야 한다. GitHub 밖으로 저장소를 옮기면 PR 댓글이 따라오지 않는다.

## 다시 볼 조건

GitHub 밖으로 이전하거나, PR 댓글만으로 재구성 절차를 찾기 어렵다는 문제가 실제로 생기면 다시 본다.

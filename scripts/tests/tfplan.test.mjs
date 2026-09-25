import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const script = fileURLToPath(new URL("../tfplan.sh", import.meta.url));

function check(resourceChanges) {
  const directory = mkdtempSync(join(tmpdir(), "tfplan-policy-"));
  const plan = join(directory, "plan.json");
  try {
    writeFileSync(plan, JSON.stringify({ resource_changes: resourceChanges }));
    return spawnSync("bash", [script, "check-foundation", plan], { encoding: "utf8" });
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

function change(address, actions, replacePaths) {
  return { address, change: { actions, replace_paths: replacePaths } };
}

test("prod 웹 태스크 정의의 컨테이너 선생성 교체와 서비스 수정은 검사를 통과한다", () => {
  const result = check([
    change("module.web.aws_ecs_task_definition.web", ["create", "delete"], [["container_definitions"]]),
    change("module.web.aws_ecs_service.web", ["update"]),
  ]);
  assert.equal(result.status, 0, result.stderr || result.stdout);
});

test("prod 웹 태스크 정의의 삭제 우선 교체는 검사를 거부한다", () => {
  const result = check([
    change("module.web.aws_ecs_task_definition.web", ["delete", "create"], [["container_definitions"]]),
  ]);
  assert.equal(result.status, 1);
});

test("EC2 호스트의 선생성 교체는 검사를 거부한다", () => {
  const result = check([
    change("module.ecs_host.aws_instance.web", ["create", "delete"], [["instance_type"]]),
  ]);
  assert.equal(result.status, 1);
});

test("prod 웹 태스크 정의의 컨테이너 외 변경 교체는 검사를 거부한다", () => {
  const result = check([
    change("module.web.aws_ecs_task_definition.web", ["create", "delete"], [["execution_role_arn"]]),
  ]);
  assert.equal(result.status, 1);
});

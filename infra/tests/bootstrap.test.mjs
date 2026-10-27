// 저장된 bootstrap plan의 공통 IAM 경계를 검증한다. 환경별 앱 배포 역할과 ECS 인프라 역할은
// environment.test.mjs가 검증한다.
// PLAN_JSON=<terraform show -json 출력> node --test infra/tests/bootstrap.test.mjs
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { account, after, decide, plan, repository, roleDocuments } from "./plan-policy.mjs";

const executionRole = await roleDocuments("aws-fullstack-lab-ecs-task-execution");

describe("공통 IAM 경계", () => {
  for (const environment of ["preprod", "prod"]) {
    test(`ECS 실행 역할은 ${environment} 이미지 pull을 허용한다`, async () => {
      assert.equal(await decide(executionRole, "ecr:BatchGetImage", repository(environment)), "allowed");
    });
  }

  test("bootstrap plan에는 환경별 앱 배포 역할이 없다", () => {
    const appRoles = plan.resource_changes.filter(({ type, change }) =>
      type === "aws_iam_role" && change.after?.name?.startsWith("aws-fullstack-lab-app-"));
    assert.deepEqual(appRoles, []);
  });

  test("ECS 호스트 역할에는 SSM 관리 정책이 연결된다", () => {
    const attachment = after["module.iam.aws_iam_role_policy_attachment.ecs_host_ssm"];
    assert.equal(attachment.role, "aws-fullstack-lab-ecs-host");
    assert.equal(attachment.policy_arn, "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore");
  });

  test("운영 역할 신뢰 정책은 사용자와 MFA를 요구한다", () => {
    const trust = JSON.parse(after["module.iam.aws_iam_role.operator"].assume_role_policy);
    const statement = trust.Statement[0];
    assert.equal(statement.Principal.AWS, `arn:aws:iam::${account}:user/aws-fullstack-lab-operator`);
    assert.equal(statement.Condition.Bool["aws:MultiFactorAuthPresent"], "true");
  });
});

// 저장된 bootstrap plan의 핵심 IAM 경계를 AWS 정책 시뮬레이터로 검증한다. 역할마다 plan의
// 인라인 정책과 연결된 AWS 관리형 정책의 현재 기본 버전을 함께 평가한다.
// PLAN_JSON=<terraform show -json 출력> node --test infra/bootstrap/tests/iam.test.mjs
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { readFileSync } from "node:fs";
import { describe, test } from "node:test";
import { promisify } from "node:util";

const run = promisify(execFile);
const plan = JSON.parse(readFileSync(process.env.PLAN_JSON, "utf8"));
const after = Object.fromEntries(plan.resource_changes.map(({ address, change }) => [address, change.after]));
const account = plan.variables.expected_account_id.value;
const region = plan.variables.aws_region.value;
const bucket = `arn:aws:s3:::${plan.variables.state_bucket_name.value}`;
const role = (name) => `arn:aws:iam::${account}:role/aws-fullstack-lab-${name}`;
const repository = (environment) => `arn:aws:ecr:${region}:${account}:repository/aws-fullstack-lab-${environment}-web`;

async function aws(...args) {
  const { stdout } = await run("aws", [...args, "--output", "json"], { maxBuffer: 16 * 1024 * 1024 });
  return JSON.parse(stdout);
}

async function managedPolicy(arn) {
  const version = await aws("iam", "get-policy", "--policy-arn", arn, "--query", "Policy.DefaultVersionId");
  return JSON.stringify(await aws("iam", "get-policy-version", "--policy-arn", arn, "--version-id", version, "--query", "PolicyVersion.Document"));
}

// plan에서 역할 이름으로 인라인 정책과 관리형 정책 연결을 모은다.
async function roleDocuments(name) {
  const resources = plan.resource_changes.filter(({ change }) => change.after?.role === name);
  const inline = resources.filter(({ type }) => type === "aws_iam_role_policy").map(({ change }) => change.after.policy);
  const managed = resources.filter(({ type }) => type === "aws_iam_role_policy_attachment").map(({ change }) => change.after.policy_arn);
  return [...inline, ...(await Promise.all(managed.map(managedPolicy)))];
}

const appRoles = Object.fromEntries(await Promise.all(["preprod", "prod"].map(async (environment) =>
  [environment, await roleDocuments(`aws-fullstack-lab-app-${environment}`)])));
const executionRole = await roleDocuments("aws-fullstack-lab-ecs-task-execution");

async function decide(documents, action, resource, context = {}) {
  const entries = Object.entries(context).map(([key, value]) => ({
    ContextKeyName: key,
    ContextKeyValues: [String(value)],
    ContextKeyType: "string",
  }));
  const result = await aws(
    "iam", "simulate-custom-policy", "--policy-input-list", ...documents,
    "--action-names", action, "--resource-arns", resource,
    "--context-entries", JSON.stringify(entries),
  );
  return result.EvaluationResults[0].EvalDecision;
}

function trustedSubjects(key) {
  const trust = JSON.parse(after[`module.iam.aws_iam_role.github["${key}"]`].assume_role_policy);
  return trust.Statement.flatMap((statement) => [].concat(statement.Condition.StringEquals["token.actions.githubusercontent.com:sub"]));
}

for (const environment of ["preprod", "prod"]) {
  describe(`${environment} 공통 역할`, () => {
    test(`${environment} 앱 역할은 해당 환경 이미지 push를 허용하고 다른 환경 push를 거부한다`, async () => {
      const other = environment === "preprod" ? "prod" : "preprod";
      assert.equal(await decide(appRoles[environment], "ecr:PutImage", repository(environment)), "allowed");
      assert.equal(await decide(appRoles[environment], "ecr:PutImage", repository(other)), "implicitDeny");
      assert.equal(await decide(appRoles[environment], "ecr:DeleteRepository", repository(environment)), "implicitDeny");
    });

    test(`${environment} 앱 역할은 해당 ECS 서비스 배포를 허용하고 다른 서비스 변경을 거부한다`, async () => {
      const other = environment === "preprod" ? "prod" : "preprod";
      const service = (env) => `arn:aws:ecs:${region}:${account}:service/aws-fullstack-lab-${env}-cluster/web`;
      const taskDefinition = (env) => `arn:aws:ecs:${region}:${account}:task-definition/aws-fullstack-lab-${env}-web:1`;
      assert.equal(await decide(appRoles[environment], "ecs:UpdateService", service(environment)), "allowed");
      assert.equal(await decide(appRoles[environment], "ecs:UpdateService", service(other)), "implicitDeny");
      assert.equal(await decide(appRoles[environment], "ecs:RegisterTaskDefinition", taskDefinition(environment)), "allowed");
      assert.equal(await decide(appRoles[environment], "ecs:RegisterTaskDefinition", taskDefinition(other)), "implicitDeny");
      assert.equal(await decide(appRoles[environment], "iam:PassRole", role("ecs-task-execution"), { "iam:PassedToService": "ecs-tasks.amazonaws.com" }), "allowed");
      assert.equal(await decide(appRoles[environment], "iam:PassRole", role("bootstrap-operator"), { "iam:PassedToService": "ecs-tasks.amazonaws.com" }), "implicitDeny");
    });

    test(`${environment} 실행 역할은 이미지 pull을 허용한다`, async () => {
      assert.equal(await decide(executionRole, "ecr:BatchGetImage", repository(environment)), "allowed");
    });
  });
}

describe("GitHub 역할", () => {
  test("GitHub OIDC 역할은 앱 저장소의 preprod 브랜치와 prod-deploy 환경만 신뢰한다", () => {
    const subject = plan.variables.app_repository_subject.value;
    const keys = plan.resource_changes
      .filter(({ address, change }) => address.startsWith("module.iam.aws_iam_role.github[") && change.after)
      .map(({ index }) => index);
    assert.deepEqual(keys.sort(), ["app-preprod", "app-prod"]);
    assert.deepEqual(trustedSubjects("app-preprod"), [`${subject}:ref:refs/heads/preprod`]);
    assert.deepEqual(trustedSubjects("app-prod"), [`${subject}:environment:prod-deploy`]);
  });

  test("prod 앱 역할은 ALB 대상 조회를 허용하고 preprod 앱 역할은 거부한다", async () => {
    assert.equal(await decide(appRoles.prod, "elasticloadbalancing:DescribeTargetHealth", "*"), "allowed");
    assert.equal(await decide(appRoles.preprod, "elasticloadbalancing:DescribeTargetHealth", "*"), "implicitDeny");
  });

  test("prod 앱 역할은 prod 서비스의 배포 이력 조회를 허용하고 preprod 서비스 조회를 거부한다", async () => {
    const history = (env) => `arn:aws:ecs:${region}:${account}:service-deployment/aws-fullstack-lab-${env}-cluster/web/example`;
    const revision = (env) => `arn:aws:ecs:${region}:${account}:service-revision/aws-fullstack-lab-${env}-cluster/web/1`;
    assert.equal(await decide(appRoles.prod, "ecs:DescribeServiceDeployments", history("prod")), "allowed");
    assert.equal(await decide(appRoles.prod, "ecs:DescribeServiceRevisions", revision("prod")), "allowed");
    assert.equal(await decide(appRoles.prod, "ecs:DescribeServiceDeployments", history("preprod")), "implicitDeny");
    assert.equal(await decide(appRoles.preprod, "ecs:DescribeServiceDeployments", history("preprod")), "implicitDeny");
  });

  test("앱 역할은 bootstrap state 읽기를 거부한다", async () => {
    for (const documents of Object.values(appRoles)) {
      assert.notEqual(await decide(documents, "s3:GetObject", `${bucket}/bootstrap/terraform.tfstate`), "allowed");
    }
  });

  test("앱 역할은 인프라 변경과 IAM 역할 생성을 거부한다", async () => {
    for (const documents of Object.values(appRoles)) {
      assert.equal(await decide(documents, "ec2:CreateVpc", `arn:aws:ec2:${region}:${account}:vpc/*`), "implicitDeny");
      assert.equal(await decide(documents, "iam:CreateRole", role("extra")), "implicitDeny");
    }
  });
});

describe("공통 IAM 경계", () => {
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

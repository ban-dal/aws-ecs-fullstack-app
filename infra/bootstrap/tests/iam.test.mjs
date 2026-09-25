// 저장된 bootstrap plan의 핵심 IAM 경계를 AWS 정책 시뮬레이터로 검증한다.
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
const policy = (address) => after[address].policy;

// 연결된 AWS 관리형 정책은 plan에 본문이 없으므로 현재 기본 버전을 받아 함께 평가한다.
async function managed(address) {
  const arn = after[address].policy_arn;
  const version = (await run("aws", ["iam", "get-policy", "--policy-arn", arn, "--query", "Policy.DefaultVersionId", "--output", "text"])).stdout.trim();
  const { stdout } = await run("aws", ["iam", "get-policy-version", "--policy-arn", arn, "--version-id", version, "--query", "PolicyVersion.Document", "--output", "json"]);
  return JSON.stringify(JSON.parse(stdout));
}

const planPolicy = [policy('module.iam.aws_iam_role_policy.github["plan"]'), await managed('module.iam.aws_iam_role_policy_attachment.github["plan"]')];
const applyPolicy = [policy('module.iam.aws_iam_role_policy.github["apply"]'), await managed('module.iam.aws_iam_role_policy_attachment.github["apply"]')];
const imagePolicy = [policy('module.iam.aws_iam_role_policy.github["image"]')];
const executionPolicy = [policy("module.iam.aws_iam_role_policy.ecs_execution")];
const powerUser = "arn:aws:iam::aws:policy/PowerUserAccess";

async function decide(documents, action, resource, context = {}) {
  const entries = Object.entries(context).map(([key, value]) => ({
    ContextKeyName: key,
    ContextKeyValues: [String(value)],
    ContextKeyType: "string",
  }));
  const { stdout } = await run("aws", [
    "iam", "simulate-custom-policy", "--output", "json", "--policy-input-list", ...documents,
    "--action-names", action, "--resource-arns", resource,
    "--context-entries", JSON.stringify(entries),
  ]);
  return JSON.parse(stdout).EvaluationResults[0].EvalDecision;
}

for (const environment of ["preprod", "prod"]) {
  describe(`${environment} 공통 역할`, () => {
    test(`${environment} plan은 state 읽기를 허용하고 본문 쓰기를 거부한다`, async () => {
      const state = `${bucket}/${environment}/terraform.tfstate`;
      assert.equal(await decide(planPolicy, "s3:GetObject", state), "allowed");
      assert.equal(await decide(planPolicy, "s3:PutObject", state), "implicitDeny");
    });

    test(`${environment} plan은 ALB 조회를 허용한다`, async () => {
      assert.equal(await decide(planPolicy, "elasticloadbalancing:DescribeLoadBalancers", "*"), "allowed");
    });

    test(`${environment} apply는 state 쓰기와 ALB를 포함한 서비스 변경을 허용한다`, async () => {
      assert.equal(await decide(applyPolicy, "s3:PutObject", `${bucket}/${environment}/terraform.tfstate`), "allowed");
      assert.equal(await decide(applyPolicy, "ec2:CreateVpc", `arn:aws:ec2:${region}:${account}:vpc/*`), "allowed");
      assert.equal(await decide(applyPolicy, "elasticloadbalancing:CreateLoadBalancer", `arn:aws:elasticloadbalancing:${region}:${account}:loadbalancer/app/aws-fullstack-lab-${environment}-web/*`), "allowed");
    });

    test(`${environment} apply는 PowerUserAccess 경계가 있을 때만 환경 역할 생성을 허용한다`, async () => {
      const taskRole = role(`${environment}-web-task`);
      assert.equal(await decide(applyPolicy, "iam:CreateRole", taskRole, { "iam:PermissionsBoundary": powerUser }), "allowed");
      assert.equal(await decide(applyPolicy, "iam:CreateRole", taskRole), "implicitDeny");
      assert.equal(await decide(applyPolicy, "iam:PassRole", taskRole, { "iam:PassedToService": "ecs-tasks.amazonaws.com" }), "allowed");
    });

    test(`${environment} apply는 저장소 관리와 공통 ECS 역할 전달을 허용한다`, async () => {
      assert.equal(await decide(applyPolicy, "ecr:CreateRepository", repository(environment)), "allowed");
      assert.equal(await decide(applyPolicy, "iam:PassRole", role("ecs-host"), { "iam:PassedToService": "ec2.amazonaws.com" }), "allowed");
      assert.equal(await decide(applyPolicy, "iam:PassRole", role("ecs-host"), { "iam:PassedToService": "ecs-tasks.amazonaws.com" }), "implicitDeny");
    });

    test(`${environment} image는 이미지 push를 허용하고 저장소 삭제를 거부한다`, async () => {
      assert.equal(await decide(imagePolicy, "ecr:PutImage", repository(environment)), "allowed");
      assert.equal(await decide(imagePolicy, "ecr:DeleteRepository", repository(environment)), "implicitDeny");
    });

    test(`${environment} 실행 역할은 이미지 pull을 허용한다`, async () => {
      assert.equal(await decide(executionPolicy, "ecr:BatchGetImage", repository(environment)), "allowed");
    });
  });
}

describe("공통 IAM 경계", () => {
  test("ECS 호스트의 SSM 관리 권한은 연결되고 GitHub apply는 IAM 정책 연결을 거부한다", async () => {
    const attachment = after["module.iam.aws_iam_role_policy_attachment.ecs_host_ssm"];
    assert.equal(attachment.role, "aws-fullstack-lab-ecs-host");
    assert.equal(attachment.policy_arn, "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore");
    assert.equal(await decide(applyPolicy, "iam:AttachRolePolicy", role("ecs-host")), "implicitDeny");
  });

  test("plan과 image 역할은 bootstrap state 읽기를 거부한다", async () => {
    assert.equal(await decide(planPolicy, "s3:GetObject", `${bucket}/bootstrap/terraform.tfstate`), "explicitDeny");
    assert.equal(await decide(imagePolicy, "s3:GetObject", `${bucket}/bootstrap/terraform.tfstate`), "implicitDeny");
  });

  test("GitHub 역할은 환경 밖 IAM 역할 생성과 IAM 사용자 생성을 거부한다", async () => {
    for (const documents of [planPolicy, applyPolicy, imagePolicy]) {
      assert.equal(await decide(documents, "iam:CreateRole", role("extra"), { "iam:PermissionsBoundary": powerUser }), "implicitDeny");
      assert.equal(await decide(documents, "iam:CreateUser", `arn:aws:iam::${account}:user/extra`), "implicitDeny");
    }
  });

  test("운영 역할 신뢰 정책은 사용자와 MFA를 요구한다", () => {
    const trust = JSON.parse(after["module.iam.aws_iam_role.operator"].assume_role_policy);
    const statement = trust.Statement[0];
    assert.equal(statement.Principal.AWS, `arn:aws:iam::${account}:user/aws-fullstack-lab-operator`);
    assert.equal(statement.Condition.Bool["aws:MultiFactorAuthPresent"], "true");
  });
});

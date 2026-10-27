// 저장된 환경 루트 plan의 앱 배포 역할과 prod ECS 인프라 역할을 검증한다.
// ENVIRONMENT=<preprod|prod> STATE_BUCKET=<state 버킷> PLAN_JSON=<terraform show -json 출력> \
//   node --test infra/tests/environment.test.mjs
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { account, after, decide, region, repository, role, roleDocuments } from "./plan-policy.mjs";

const environment = process.env.ENVIRONMENT;
assert.ok(["preprod", "prod"].includes(environment), "ENVIRONMENT는 preprod 또는 prod여야 한다");
const other = environment === "preprod" ? "prod" : "preprod";
const appRole = await roleDocuments(`aws-fullstack-lab-app-${environment}`);
const service = (env) => `arn:aws:ecs:${region}:${account}:service/aws-fullstack-lab-${env}-cluster/web`;
const ecs = { "iam:PassedToService": "ecs.amazonaws.com" };

describe(`${environment} 앱 배포 역할`, () => {
  test(`${environment} 앱 역할은 해당 환경 이미지 push를 허용하고 다른 환경 push를 거부한다`, async () => {
    assert.equal(await decide(appRole, "ecr:PutImage", repository(environment)), "allowed");
    assert.equal(await decide(appRole, "ecr:PutImage", repository(other)), "implicitDeny");
    assert.equal(await decide(appRole, "ecr:DeleteRepository", repository(environment)), "implicitDeny");
  });

  test(`${environment} 앱 역할은 해당 ECS 서비스 배포를 허용하고 다른 서비스 변경을 거부한다`, async () => {
    const taskDefinition = (env) => `arn:aws:ecs:${region}:${account}:task-definition/aws-fullstack-lab-${env}-web:1`;
    assert.equal(await decide(appRole, "ecs:UpdateService", service(environment)), "allowed");
    assert.equal(await decide(appRole, "ecs:UpdateService", service(other)), "implicitDeny");
    assert.equal(await decide(appRole, "ecs:RegisterTaskDefinition", taskDefinition(environment)), "allowed");
    assert.equal(await decide(appRole, "ecs:RegisterTaskDefinition", taskDefinition(other)), "implicitDeny");
    assert.equal(await decide(appRole, "iam:PassRole", role("ecs-task-execution"), { "iam:PassedToService": "ecs-tasks.amazonaws.com" }), "allowed");
    assert.equal(await decide(appRole, "iam:PassRole", role("bootstrap-operator"), { "iam:PassedToService": "ecs-tasks.amazonaws.com" }), "implicitDeny");
  });

  test(`${environment} 앱 역할은 해당 서비스의 배포 이력 조회를 허용하고 다른 환경 조회를 거부한다`, async () => {
    const history = (env) => `arn:aws:ecs:${region}:${account}:service-deployment/aws-fullstack-lab-${env}-cluster/web/example`;
    const revision = (env) => `arn:aws:ecs:${region}:${account}:service-revision/aws-fullstack-lab-${env}-cluster/web/1`;
    assert.equal(await decide(appRole, "ecs:DescribeServiceDeployments", history(environment)), "allowed");
    assert.equal(await decide(appRole, "ecs:DescribeServiceRevisions", revision(environment)), "allowed");
    assert.equal(await decide(appRole, "ecs:DescribeServiceDeployments", history(other)), "implicitDeny");
  });

  test(`${environment} 앱 역할은 앱 저장소의 ${environment} 배포 조건만 신뢰한다`, () => {
    const trust = JSON.parse(after["module.app_deploy.aws_iam_role.this"].assume_role_policy);
    const subjects = trust.Statement.flatMap((statement) => [].concat(statement.Condition.StringEquals["token.actions.githubusercontent.com:sub"]));
    const condition = environment === "preprod" ? "ref:refs/heads/preprod" : "environment:prod-deploy";
    assert.deepEqual(subjects, [`repo:ban-dal@46153202/aws-ecs-fullstack-web@1386828063:${condition}`]);
  });

  test(`${environment} 앱 역할은 state 읽기와 인프라 변경, IAM 역할 생성을 거부한다`, async () => {
    assert.notEqual(await decide(appRole, "s3:GetObject", `arn:aws:s3:::${process.env.STATE_BUCKET}/bootstrap/terraform.tfstate`), "allowed");
    assert.equal(await decide(appRole, "ec2:CreateVpc", `arn:aws:ec2:${region}:${account}:vpc/*`), "implicitDeny");
    assert.equal(await decide(appRole, "iam:CreateRole", role("extra")), "implicitDeny");
  });

  if (environment === "preprod") {
    test("preprod 앱 역할은 ALB 대상 조회와 ECS 인프라 역할 전달을 거부한다", async () => {
      assert.equal(await decide(appRole, "elasticloadbalancing:DescribeTargetHealth", "*"), "implicitDeny");
      assert.equal(await decide(appRole, "iam:PassRole", role("ecs-infrastructure"), ecs), "implicitDeny");
    });
  }
});

if (environment === "prod") {
  describe("prod blue/green", () => {
    test("prod 앱 역할은 ALB 대상 조회와 ECS에 인프라 역할 전달을 허용하고 다른 서비스로의 전달은 거부한다", async () => {
      assert.equal(await decide(appRole, "elasticloadbalancing:DescribeTargetHealth", "*"), "allowed");
      assert.equal(await decide(appRole, "iam:PassRole", role("ecs-infrastructure"), ecs), "allowed");
      assert.equal(await decide(appRole, "iam:PassRole", role("ecs-infrastructure"), { "iam:PassedToService": "lambda.amazonaws.com" }), "implicitDeny");
      assert.equal(await decide(appRole, "iam:PassRole", role("bootstrap-operator"), ecs), "implicitDeny");
    });

    test("ECS 인프라 역할은 같은 계정의 ECS만 신뢰하고 리스너 규칙 변경을 허용하며 EC2 종료는 거부한다", async () => {
      const trust = JSON.parse(after["module.web.aws_iam_role.ecs_infrastructure"].assume_role_policy);
      assert.deepEqual(trust.Statement.map(({ Principal }) => Principal.Service), ["ecs.amazonaws.com"]);
      assert.equal(trust.Statement[0].Condition.StringEquals["aws:SourceAccount"], account);
      const infrastructureRole = await roleDocuments("aws-fullstack-lab-ecs-infrastructure");
      const rule = `arn:aws:elasticloadbalancing:${region}:${account}:listener-rule/app/aws-fullstack-lab-prod-web/example/example/example`;
      assert.equal(await decide(infrastructureRole, "elasticloadbalancing:ModifyRule", rule), "allowed");
      assert.equal(await decide(infrastructureRole, "ec2:TerminateInstances", `arn:aws:ec2:${region}:${account}:instance/*`), "implicitDeny");
    });
  });
}

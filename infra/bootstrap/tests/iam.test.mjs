// bootstrap IAM 권한의 의도를 실행 가능한 형태로 적은 테스트다. 각 사례는 저장된
// bootstrap plan의 정책을 IAM 정책 시뮬레이터로 판정한다. 의도한 경계를 깨는 정책
// 변경은 적용되기 전에 여기서 실패한다.
//
// scripts/bootstrap.sh plan에서 실행되며, 직접 실행할 수도 있다.
//   PLAN_JSON=<terraform show -json 출력> node --test infra/bootstrap/tests/*.test.mjs
// iam:SimulateCustomPolicy를 호출할 수 있는 AWS 자격 증명이 필요하다.

import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { readFileSync } from "node:fs";
import { describe, test } from "node:test";
import { promisify } from "node:util";

const run = promisify(execFile);

const plan = JSON.parse(readFileSync(process.env.PLAN_JSON, "utf8"));
const after = Object.fromEntries(plan.resource_changes.map((change) => [change.address, change.change.after]));
const variable = (name) => plan.variables[name].value;

const account = variable("expected_account_id");
const region = variable("aws_region");
const bucket = `arn:aws:s3:::${variable("state_bucket_name")}`;
const ec2 = `arn:aws:ec2:${region}:${account}`;
const role = (name) => `arn:aws:iam::${account}:role/${name}`;
const boundaryArn = `arn:aws:iam::${account}:policy/${after["module.iam_github_oidc.aws_iam_policy.boundary"].name}`;

const boundary = after["module.iam_github_oidc.aws_iam_policy.boundary"].policy;
const operator = after["module.iam_operator.aws_iam_role_policy.this"].policy;
const admin = JSON.stringify({ Version: "2012-10-17", Statement: [{ Effect: "Allow", Action: "*", Resource: "*" }] });
const inRegion = { "aws:RequestedRegion": region };

async function decide({ policies, boundaries = [], action, resource, context = {} }) {
  const entries = Object.entries(context).map(([key, value]) => ({
    ContextKeyName: key,
    ContextKeyValues: Array.isArray(value) ? value : [value],
    ContextKeyType: Array.isArray(value) ? "stringList" : "string",
  }));
  const args = ["iam", "simulate-custom-policy", "--output", "json", "--policy-input-list", ...policies];
  if (boundaries.length > 0) args.push("--permissions-boundary-policy-input-list", ...boundaries);
  args.push("--action-names", action, "--resource-arns", resource, "--context-entries", JSON.stringify(entries));
  const { stdout } = await run("aws", args);
  return JSON.parse(stdout).EvaluationResults[0].EvalDecision;
}

for (const [environment, other] of [["preprod", "prod"], ["prod", "preprod"]]) {
  const apply = { policies: [after[`module.iam_github_apply.aws_iam_role_policy.this["${environment}"]`].policy], boundaries: [boundary] };
  const planRole = { policies: [after[`module.iam_github_plan.aws_iam_role_policy.this["${environment}"]`].policy], boundaries: [boundary] };
  const own = { ...inRegion, "aws:ResourceTag/Environment": environment };
  const foreign = { ...inRegion, "aws:ResourceTag/Environment": other };
  const repository = (name) => `arn:aws:ecr:${region}:${account}:repository/aws-fullstack-lab-${name}-web`;
  const ecs = `arn:aws:ecs:${region}:${account}`;
  const logGroup = (name) => `arn:aws:logs:${region}:${account}:log-group:aws-fullstack-lab-${name}-web`;
  const hostGroup = (name) => `arn:aws:autoscaling:${region}:${account}:autoScalingGroup:00000000-0000-0000-0000-000000000000:autoScalingGroupName/aws-fullstack-lab-${name}-ecs-hosts`;

  describe(`${environment} 적용 역할`, () => {
    test(`${environment} 태그를 요청한 VPC 생성은 허용된다`, async () => {
      assert.equal(await decide({ ...apply, action: "ec2:CreateVpc", resource: `${ec2}:vpc/*`, context: { ...inRegion, "aws:RequestTag/Environment": environment } }), "allowed");
    });
    test(`${other} 태그를 요청한 VPC 생성은 거부된다`, async () => {
      assert.equal(await decide({ ...apply, action: "ec2:CreateVpc", resource: `${ec2}:vpc/*`, context: { ...inRegion, "aws:RequestTag/Environment": other } }), "implicitDeny");
    });
    test(`${environment} VPC 안의 서브넷 생성은 허용된다`, async () => {
      assert.equal(await decide({ ...apply, action: "ec2:CreateSubnet", resource: `${ec2}:vpc/vpc-own`, context: { ...own, "aws:RequestTag/Environment": environment } }), "allowed");
    });
    test(`${other} VPC 안의 서브넷 생성은 자기 태그를 요청해도 거부된다`, async () => {
      assert.equal(await decide({ ...apply, action: "ec2:CreateSubnet", resource: `${ec2}:vpc/vpc-other`, context: { ...foreign, "aws:RequestTag/Environment": environment } }), "implicitDeny");
    });
    test("생성 시점의 태그 지정은 자기 환경 값일 때만 허용된다", async () => {
      const context = { ...inRegion, "ec2:CreateAction": "CreateVpc" };
      assert.equal(await decide({ ...apply, action: "ec2:CreateTags", resource: `${ec2}:vpc/*`, context: { ...context, "aws:RequestTag/Environment": environment } }), "allowed");
      assert.equal(await decide({ ...apply, action: "ec2:CreateTags", resource: `${ec2}:vpc/*`, context: { ...context, "aws:RequestTag/Environment": other } }), "implicitDeny");
    });
    test(`${environment} VPC 삭제는 허용되고 ${other} VPC 삭제는 거부된다`, async () => {
      assert.equal(await decide({ ...apply, action: "ec2:DeleteVpc", resource: `${ec2}:vpc/vpc-own`, context: own }), "allowed");
      assert.equal(await decide({ ...apply, action: "ec2:DeleteVpc", resource: `${ec2}:vpc/vpc-other`, context: foreign }), "implicitDeny");
    });
    test(`${other} 보안 그룹의 규칙 추가는 거부된다`, async () => {
      assert.equal(await decide({ ...apply, action: "ec2:AuthorizeSecurityGroupIngress", resource: `${ec2}:security-group/sg-own`, context: own }), "allowed");
      assert.equal(await decide({ ...apply, action: "ec2:AuthorizeSecurityGroupIngress", resource: `${ec2}:security-group/sg-other`, context: foreign }), "implicitDeny");
    });
    test("태그 없는 보안 그룹 규칙 리소스는 허용된다", async () => {
      assert.equal(await decide({ ...apply, action: "ec2:AuthorizeSecurityGroupIngress", resource: `${ec2}:security-group-rule/sgr-new`, context: inRegion }), "allowed");
    });
    test(`자기 리소스의 Environment 태그를 ${other}로 바꾸는 요청은 거부된다`, async () => {
      assert.equal(await decide({ ...apply, action: "ec2:CreateTags", resource: `${ec2}:subnet/subnet-own`, context: { ...own, "aws:TagKeys": ["Name"], "aws:RequestTag/Name": "web" } }), "allowed");
      assert.equal(await decide({ ...apply, action: "ec2:CreateTags", resource: `${ec2}:subnet/subnet-own`, context: { ...own, "aws:RequestTag/Environment": other } }), "implicitDeny");
    });
    test(`${other} 리소스에 ${environment} 태그를 붙이는 요청은 거부된다`, async () => {
      assert.equal(await decide({ ...apply, action: "ec2:CreateTags", resource: `${ec2}:subnet/subnet-other`, context: { ...foreign, "aws:RequestTag/Environment": environment } }), "implicitDeny");
    });
    test("Environment 태그 제거는 거부되고 다른 태그 제거는 허용된다", async () => {
      assert.equal(await decide({ ...apply, action: "ec2:DeleteTags", resource: `${ec2}:subnet/subnet-own`, context: { ...own, "aws:TagKeys": ["Name"] } }), "allowed");
      assert.equal(await decide({ ...apply, action: "ec2:DeleteTags", resource: `${ec2}:subnet/subnet-own`, context: { ...own, "aws:TagKeys": ["Environment"] } }), "implicitDeny");
    });
    test("다른 리전의 조회는 거부된다", async () => {
      assert.equal(await decide({ ...apply, action: "ec2:DescribeVpcs", resource: "*", context: inRegion }), "allowed");
      assert.equal(await decide({ ...apply, action: "ec2:DescribeVpcs", resource: "*", context: { "aws:RequestedRegion": "us-east-1" } }), "implicitDeny");
    });
    test(`${other} state 쓰기는 거부된다`, async () => {
      assert.equal(await decide({ ...apply, action: "s3:PutObject", resource: `${bucket}/${environment}/terraform.tfstate`, context: inRegion }), "allowed");
      assert.equal(await decide({ ...apply, action: "s3:PutObject", resource: `${bucket}/${other}/terraform.tfstate`, context: inRegion }), "implicitDeny");
    });
    test(`${other} ECR 저장소 생성은 거부된다`, async () => {
      assert.equal(await decide({ ...apply, action: "ecr:CreateRepository", resource: repository(environment), context: inRegion }), "allowed");
      assert.equal(await decide({ ...apply, action: "ecr:CreateRepository", resource: repository(other), context: inRegion }), "implicitDeny");
    });
    test(`${environment} 호스트 역할은 EC2에만 넘길 수 있고 ${other} 호스트 역할은 넘기지 못한다`, async () => {
      const toEc2 = { ...inRegion, "iam:PassedToService": "ec2.amazonaws.com" };
      assert.equal(await decide({ ...apply, action: "iam:PassRole", resource: role(`aws-fullstack-lab-${environment}-ecs-host`), context: toEc2 }), "allowed");
      assert.equal(await decide({ ...apply, action: "iam:PassRole", resource: role(`aws-fullstack-lab-${environment}-ecs-host`), context: { ...inRegion, "iam:PassedToService": "lambda.amazonaws.com" } }), "implicitDeny");
      assert.equal(await decide({ ...apply, action: "iam:PassRole", resource: role(`aws-fullstack-lab-${other}-ecs-host`), context: toEc2 }), "implicitDeny");
    });
    test(`${environment} 태스크 실행 역할은 ECS 태스크에만 넘길 수 있다`, async () => {
      const executionRole = role(`aws-fullstack-lab-${environment}-ecs-task-execution`);
      assert.equal(await decide({ ...apply, action: "iam:PassRole", resource: executionRole, context: { ...inRegion, "iam:PassedToService": "ecs-tasks.amazonaws.com" } }), "allowed");
      assert.equal(await decide({ ...apply, action: "iam:PassRole", resource: executionRole, context: { ...inRegion, "iam:PassedToService": "ec2.amazonaws.com" } }), "implicitDeny");
    });
    test("t4g.micro 호스트 실행은 허용되고 다른 인스턴스 유형은 거부된다", async () => {
      assert.equal(await decide({ ...apply, action: "ec2:RunInstances", resource: `${ec2}:instance/*`, context: { ...inRegion, "ec2:InstanceType": "t4g.micro" } }), "allowed");
      assert.equal(await decide({ ...apply, action: "ec2:RunInstances", resource: `${ec2}:instance/*`, context: { ...inRegion, "ec2:InstanceType": "m7g.large" } }), "implicitDeny");
    });
    test(`${other} 서브넷에서 호스트 실행은 거부된다`, async () => {
      assert.equal(await decide({ ...apply, action: "ec2:RunInstances", resource: `${ec2}:subnet/subnet-own`, context: own }), "allowed");
      assert.equal(await decide({ ...apply, action: "ec2:RunInstances", resource: `${ec2}:subnet/subnet-other`, context: foreign }), "implicitDeny");
    });
    test("Amazon이 소유하지 않은 AMI로 호스트 실행은 거부된다", async () => {
      const image = `arn:aws:ec2:${region}::image/ami-0000`;
      assert.equal(await decide({ ...apply, action: "ec2:RunInstances", resource: image, context: { ...inRegion, "ec2:Owner": "amazon" } }), "allowed");
      assert.equal(await decide({ ...apply, action: "ec2:RunInstances", resource: image, context: { ...inRegion, "ec2:Owner": "aws-marketplace" } }), "implicitDeny");
    });
    test(`${environment} 이름과 태그의 Auto Scaling group 생성만 허용된다`, async () => {
      assert.equal(await decide({ ...apply, action: "autoscaling:CreateAutoScalingGroup", resource: hostGroup(environment), context: { ...inRegion, "aws:RequestTag/Environment": environment } }), "allowed");
      assert.equal(await decide({ ...apply, action: "autoscaling:CreateAutoScalingGroup", resource: hostGroup(environment), context: { ...inRegion, "aws:RequestTag/Environment": other } }), "implicitDeny");
      assert.equal(await decide({ ...apply, action: "autoscaling:UpdateAutoScalingGroup", resource: hostGroup(other), context: inRegion }), "implicitDeny");
    });
    test(`${environment} ECS 클러스터 생성은 허용되고 ${other} 이름의 클러스터 생성은 거부된다`, async () => {
      const tagged = { ...inRegion, "aws:RequestTag/Environment": environment };
      assert.equal(await decide({ ...apply, action: "ecs:CreateCluster", resource: `${ecs}:cluster/aws-fullstack-lab-${environment}-cluster`, context: tagged }), "allowed");
      assert.equal(await decide({ ...apply, action: "ecs:CreateCluster", resource: `${ecs}:cluster/aws-fullstack-lab-${other}-cluster`, context: tagged }), "implicitDeny");
    });
    test(`${other} 클러스터 안의 서비스 생성은 거부된다`, async () => {
      const tagged = { ...inRegion, "aws:RequestTag/Environment": environment };
      assert.equal(await decide({ ...apply, action: "ecs:CreateService", resource: `${ecs}:service/aws-fullstack-lab-${environment}-cluster/aws-fullstack-lab-${environment}-web`, context: tagged }), "allowed");
      assert.equal(await decide({ ...apply, action: "ecs:CreateService", resource: `${ecs}:service/aws-fullstack-lab-${other}-cluster/aws-fullstack-lab-${environment}-web`, context: tagged }), "implicitDeny");
    });
    test(`${other} 태그를 요청한 태스크 정의 등록은 거부된다`, async () => {
      assert.equal(await decide({ ...apply, action: "ecs:RegisterTaskDefinition", resource: "*", context: { ...inRegion, "aws:RequestTag/Environment": environment } }), "allowed");
      assert.equal(await decide({ ...apply, action: "ecs:RegisterTaskDefinition", resource: "*", context: { ...inRegion, "aws:RequestTag/Environment": other } }), "implicitDeny");
    });
    test(`${environment} 로그 그룹 생성은 허용되고 ${other} 로그 그룹 생성은 거부된다`, async () => {
      assert.equal(await decide({ ...apply, action: "logs:CreateLogGroup", resource: logGroup(environment), context: inRegion }), "allowed");
      assert.equal(await decide({ ...apply, action: "logs:CreateLogGroup", resource: logGroup(other), context: inRegion }), "implicitDeny");
    });
  });

  describe(`${environment} 태스크 실행 역할`, () => {
    const execution = { policies: [after[`module.iam_ecs_roles.aws_iam_role_policy.execution["${environment}"]`].policy] };

    test(`${environment} 저장소 pull은 허용되고 ${other} 저장소 pull은 거부된다`, async () => {
      assert.equal(await decide({ ...execution, action: "ecr:BatchGetImage", resource: repository(environment) }), "allowed");
      assert.equal(await decide({ ...execution, action: "ecr:BatchGetImage", resource: repository(other) }), "implicitDeny");
    });
    test(`${environment} 로그 쓰기는 허용되고 ${other} 로그 쓰기는 거부된다`, async () => {
      assert.equal(await decide({ ...execution, action: "logs:PutLogEvents", resource: `${logGroup(environment)}:log-stream:web/1` }), "allowed");
      assert.equal(await decide({ ...execution, action: "logs:PutLogEvents", resource: `${logGroup(other)}:log-stream:web/1` }), "implicitDeny");
    });
  });

  describe(`${environment} 이미지 역할`, () => {
    const image = { policies: [after[`module.iam_github_image.aws_iam_role_policy.this["${environment}"]`].policy], boundaries: [boundary] };

    test(`${environment} 저장소에 이미지 push는 허용되고 ${other} 저장소 push는 거부된다`, async () => {
      assert.equal(await decide({ ...image, action: "ecr:PutImage", resource: repository(environment), context: inRegion }), "allowed");
      assert.equal(await decide({ ...image, action: "ecr:PutImage", resource: repository(other), context: inRegion }), "implicitDeny");
    });
    test("레지스트리 로그인은 이 리전에서만 허용된다", async () => {
      assert.equal(await decide({ ...image, action: "ecr:GetAuthorizationToken", resource: "*", context: inRegion }), "allowed");
      assert.equal(await decide({ ...image, action: "ecr:GetAuthorizationToken", resource: "*", context: { "aws:RequestedRegion": "us-east-1" } }), "implicitDeny");
    });
    test("저장소 삭제와 이미지 삭제는 거부된다", async () => {
      assert.equal(await decide({ ...image, action: "ecr:DeleteRepository", resource: repository(environment), context: inRegion }), "implicitDeny");
      assert.equal(await decide({ ...image, action: "ecr:BatchDeleteImage", resource: repository(environment), context: inRegion }), "implicitDeny");
    });
  });

  describe(`${environment} plan 역할`, () => {
    test(`${environment} state 읽기만 허용되고 쓰기는 거부된다`, async () => {
      assert.equal(await decide({ ...planRole, action: "s3:GetObject", resource: `${bucket}/${environment}/terraform.tfstate`, context: inRegion }), "allowed");
      assert.equal(await decide({ ...planRole, action: "s3:PutObject", resource: `${bucket}/${environment}/terraform.tfstate`, context: inRegion }), "implicitDeny");
    });
    test(`${other} state 읽기는 거부된다`, async () => {
      assert.equal(await decide({ ...planRole, action: "s3:GetObject", resource: `${bucket}/${other}/terraform.tfstate`, context: inRegion }), "implicitDeny");
    });
    test("ECS 조회는 허용되고 ECS 클러스터 생성은 거부된다", async () => {
      assert.equal(await decide({ ...planRole, action: "ecs:DescribeClusters", resource: "*", context: inRegion }), "allowed");
      assert.equal(await decide({ ...planRole, action: "ecs:CreateCluster", resource: `arn:aws:ecs:${region}:${account}:cluster/aws-fullstack-lab-${environment}-cluster`, context: { ...inRegion, "aws:RequestTag/Environment": environment } }), "implicitDeny");
    });
  });
}

describe("GitHub 역할 boundary", () => {
  const unlimited = { policies: [admin], boundaries: [boundary] };

  test("모든 권한을 가진 역할 정책도 IAM 역할 생성은 거부된다", async () => {
    assert.equal(await decide({ ...unlimited, action: "iam:CreateRole", resource: role("anything"), context: inRegion }), "implicitDeny");
  });
  test("모든 권한을 가진 역할 정책도 운영 역할 수임은 거부된다", async () => {
    assert.equal(await decide({ ...unlimited, action: "sts:AssumeRole", resource: role("aws-fullstack-lab-bootstrap-operator"), context: inRegion }), "implicitDeny");
  });
  test("모든 권한을 가진 역할 정책도 bootstrap state 읽기는 거부된다", async () => {
    assert.equal(await decide({ ...unlimited, action: "s3:GetObject", resource: `${bucket}/bootstrap/terraform.tfstate`, context: inRegion }), "implicitDeny");
  });
  test("모든 권한을 가진 역할 정책도 프로젝트 ECS 역할이 아닌 역할은 넘기지 못한다", async () => {
    assert.equal(await decide({ ...unlimited, action: "iam:PassRole", resource: role("aws-fullstack-lab-preprod-ecs-host"), context: inRegion }), "allowed");
    assert.equal(await decide({ ...unlimited, action: "iam:PassRole", resource: role("aws-fullstack-lab-bootstrap-operator"), context: inRegion }), "implicitDeny");
  });
  test("모든 권한을 가진 역할 정책도 다른 리전의 EC2 호출은 거부된다", async () => {
    assert.equal(await decide({ ...unlimited, action: "ec2:RunInstances", resource: `${ec2}:instance/*`, context: { "aws:RequestedRegion": "us-east-1" } }), "implicitDeny");
  });
});

describe("bootstrap 운영 역할", () => {
  const op = { policies: [operator] };
  const applyRole = role("aws-fullstack-lab-preprod-apply");

  test("GitHub 역할 정책 수정은 허용된다", async () => {
    assert.equal(await decide({ ...op, action: "iam:PutRolePolicy", resource: applyRole }), "allowed");
  });
  test("이미지 역할의 boundary 제거는 명시적으로 거부된다", async () => {
    assert.equal(await decide({ ...op, action: "iam:DeleteRolePermissionsBoundary", resource: role("aws-fullstack-lab-prod-image") }), "explicitDeny");
  });
  test("GitHub 역할의 boundary 제거는 명시적으로 거부된다", async () => {
    assert.equal(await decide({ ...op, action: "iam:DeleteRolePermissionsBoundary", resource: applyRole }), "explicitDeny");
  });
  test("다른 정책으로 boundary를 교체하는 요청은 명시적으로 거부된다", async () => {
    const context = { "iam:PermissionsBoundary": `arn:aws:iam::${account}:policy/other` };
    assert.equal(await decide({ ...op, action: "iam:PutRolePermissionsBoundary", resource: role("aws-fullstack-lab-prod-plan"), context }), "explicitDeny");
  });
  test("boundary 없는 GitHub 역할 재생성은 명시적으로 거부되고 같은 boundary로는 허용된다", async () => {
    assert.equal(await decide({ ...op, action: "iam:CreateRole", resource: applyRole }), "explicitDeny");
    assert.equal(await decide({ ...op, action: "iam:CreateRole", resource: applyRole, context: { "iam:PermissionsBoundary": boundaryArn } }), "allowed");
  });
  test("boundary 정책 읽기는 허용되고 수정은 거부된다", async () => {
    assert.equal(await decide({ ...op, action: "iam:GetPolicyVersion", resource: boundaryArn }), "allowed");
    assert.equal(await decide({ ...op, action: "iam:CreatePolicyVersion", resource: boundaryArn }), "implicitDeny");
  });
  test("ECS 역할 조회는 허용되고 정책 변경은 거부된다", async () => {
    assert.equal(await decide({ ...op, action: "iam:GetRole", resource: role("aws-fullstack-lab-prod-ecs-host") }), "allowed");
    assert.equal(await decide({ ...op, action: "iam:AttachRolePolicy", resource: role("aws-fullstack-lab-prod-ecs-host") }), "implicitDeny");
    assert.equal(await decide({ ...op, action: "iam:PutRolePolicy", resource: role("aws-fullstack-lab-prod-ecs-task-execution") }), "implicitDeny");
  });
  test("자기 역할 정책 수정은 거부된다", async () => {
    assert.equal(await decide({ ...op, action: "iam:PutRolePolicy", resource: role("aws-fullstack-lab-bootstrap-operator") }), "implicitDeny");
  });
  test("레지스트리 스캔 설정 읽기는 허용되고 변경은 거부된다", async () => {
    assert.equal(await decide({ ...op, action: "ecr:GetRegistryScanningConfiguration", resource: "*" }), "allowed");
    assert.equal(await decide({ ...op, action: "ecr:PutRegistryScanningConfiguration", resource: "*" }), "implicitDeny");
  });
  test("DNS 영역과 레코드 읽기는 허용되고 레코드 변경은 거부된다", async () => {
    const zone = "arn:aws:route53:::hostedzone/Z0000000000000";
    assert.equal(await decide({ ...op, action: "route53:ListResourceRecordSets", resource: zone }), "allowed");
    assert.equal(await decide({ ...op, action: "route53:ChangeResourceRecordSets", resource: zone }), "implicitDeny");
  });
  test("정책 시뮬레이터 호출은 허용된다", async () => {
    assert.equal(await decide({ ...op, action: "iam:SimulateCustomPolicy", resource: "*" }), "allowed");
  });
});

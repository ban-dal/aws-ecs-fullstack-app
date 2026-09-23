// bootstrap IAM 권한의 의도를 실행 가능한 형태로 적은 테스트다. 각 사례는 저장된
// bootstrap plan의 정책을 IAM 정책 시뮬레이터로 판정한다. 의도한 경계를 깨는 정책
// 변경은 적용되기 전에 여기서 실패한다.
//
// scripts/bootstrap.sh plan에서 실행되며, 직접 실행할 수도 있다.
//   PLAN_JSON=<terraform show -json 출력> node --test infra/bootstrap/policy-tests/*.test.mjs
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
const boundaryArn = `arn:aws:iam::${account}:policy/${after["aws_iam_policy.github_boundary"].name}`;

const boundary = after["aws_iam_policy.github_boundary"].policy;
const operator = after["aws_iam_role_policy.operator"].policy;
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
  const apply = { policies: [after[`aws_iam_role_policy.foundation_apply["${environment}"]`].policy], boundaries: [boundary] };
  const planRole = { policies: [after[`aws_iam_role_policy.plan["${environment}"]`].policy], boundaries: [boundary] };
  const own = { ...inRegion, "aws:ResourceTag/Environment": environment };
  const foreign = { ...inRegion, "aws:ResourceTag/Environment": other };
  const repository = (name) => `arn:aws:ecr:${region}:${account}:repository/aws-fullstack-lab-${name}-web`;

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
  });

  describe(`${environment} plan 역할`, () => {
    test(`${environment} state 읽기만 허용되고 쓰기는 거부된다`, async () => {
      assert.equal(await decide({ ...planRole, action: "s3:GetObject", resource: `${bucket}/${environment}/terraform.tfstate`, context: inRegion }), "allowed");
      assert.equal(await decide({ ...planRole, action: "s3:PutObject", resource: `${bucket}/${environment}/terraform.tfstate`, context: inRegion }), "implicitDeny");
    });
    test(`${other} state 읽기는 거부된다`, async () => {
      assert.equal(await decide({ ...planRole, action: "s3:GetObject", resource: `${bucket}/${other}/terraform.tfstate`, context: inRegion }), "implicitDeny");
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
  test("자기 역할 정책 수정은 거부된다", async () => {
    assert.equal(await decide({ ...op, action: "iam:PutRolePolicy", resource: role("aws-fullstack-lab-bootstrap-operator") }), "implicitDeny");
  });
  test("정책 시뮬레이터 호출은 허용된다", async () => {
    assert.equal(await decide({ ...op, action: "iam:SimulateCustomPolicy", resource: "*" }), "allowed");
  });
});

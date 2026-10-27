// 루트별 IAM 정책 테스트가 공유하는 helper다. 저장 plan JSON(PLAN_JSON)을 읽고, 역할마다 plan의
// 인라인 정책과 연결된 AWS 관리형 정책의 현재 기본 버전을 AWS 정책 시뮬레이터로 평가한다.
import { execFile } from "node:child_process";
import { readFileSync } from "node:fs";
import { promisify } from "node:util";

const run = promisify(execFile);

export const plan = JSON.parse(readFileSync(process.env.PLAN_JSON, "utf8"));
export const after = Object.fromEntries(plan.resource_changes.map(({ address, change }) => [address, change.after]));
export const account = plan.variables.expected_account_id.value;
export const region = plan.variables.aws_region.value;
export const role = (name) => `arn:aws:iam::${account}:role/aws-fullstack-lab-${name}`;
export const repository = (environment) => `arn:aws:ecr:${region}:${account}:repository/aws-fullstack-lab-${environment}-web`;

async function aws(...args) {
  const { stdout } = await run("aws", [...args, "--output", "json"], { maxBuffer: 16 * 1024 * 1024 });
  return JSON.parse(stdout);
}

async function managedPolicy(arn) {
  const version = await aws("iam", "get-policy", "--policy-arn", arn, "--query", "Policy.DefaultVersionId");
  return JSON.stringify(await aws("iam", "get-policy-version", "--policy-arn", arn, "--version-id", version, "--query", "PolicyVersion.Document"));
}

// plan에서 역할 이름으로 인라인 정책과 관리형 정책 연결을 모은다.
export async function roleDocuments(name) {
  const resources = plan.resource_changes.filter(({ change }) => change.after?.role === name);
  const inline = resources.filter(({ type }) => type === "aws_iam_role_policy").map(({ change }) => change.after.policy);
  const managed = resources.filter(({ type }) => type === "aws_iam_role_policy_attachment").map(({ change }) => change.after.policy_arn);
  return [...inline, ...(await Promise.all(managed.map(managedPolicy)))];
}

export async function decide(documents, action, resource, context = {}) {
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

const services = ["VPC / Subnet / Security Group", "ECR / ECS on EC2", "ALB / Route 53 / HTTPS", "S3 / Lambda"];

export default function Home() {
  return (
    <main>
      <section className="card">
        <p className="eyebrow">INFRA AS CODE · NEXT.JS</p>
        <h1>AWS 풀스택 실험실</h1>
        <p>하나의 pnpm 워크스페이스에서 앱과 Terraform 인프라를 함께 관리합니다.</p>
        <ul>{services.map((service) => <li key={service}>{service}</li>)}</ul>
        <p className="hint">환경: {process.env.APP_ENV ?? "local"}</p>
      </section>
    </main>
  );
}

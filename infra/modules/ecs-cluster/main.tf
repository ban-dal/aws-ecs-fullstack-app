# EC2 호스트가 ECS 에이전트를 등록할 클러스터를 먼저 만든다.
resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"
  tags = var.tags
}

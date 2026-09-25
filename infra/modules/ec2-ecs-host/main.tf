# ECS 호스트다. preprod는 한 AZ, prod는 두 AZ에 둔다. NAT 없이 ECR·SSM에
# 나가야 하므로 공개 서브넷에 IPv4를 명시적으로 할당하지만 공개 수신은 열지 않는다.
# ARM64 ECS AMI는 EC2 이미지 조회로 찾는다.
locals {
  subnet_ids = var.public_subnet_ids != null ? var.public_subnet_ids : [var.public_subnet_id]
}

data "aws_ami" "ecs" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-ecs-hvm-*-arm64"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

resource "aws_launch_template" "this" {
  name_prefix   = "${var.name_prefix}-ecs-"
  image_id      = data.aws_ami.ecs.id
  instance_type = "t4g.small"

  iam_instance_profile {
    name = "aws-fullstack-lab-ecs-host"
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = var.security_group_ids
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = var.imds_hop_limit
  }

  # 지속적인 고 CPU 사용에서 Unlimited 잉여 크레딧 요금이 붙지 않게 한다.
  credit_specification {
    cpu_credits = "standard"
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(<<-EOT
    #!/bin/bash
    set -euo pipefail
    echo 'ECS_CLUSTER=${var.cluster_name}' >> /etc/ecs/ecs.config
  EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.name_prefix}-ecs-host" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, { Name = "${var.name_prefix}-ecs-root" })
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-ecs-template" })
}

resource "aws_autoscaling_group" "this" {
  name                = "${var.name_prefix}-ecs"
  min_size            = var.host_count
  max_size            = var.host_count
  desired_capacity    = var.host_count
  vpc_zone_identifier = local.subnet_ids

  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }

  # launch template이 바뀌면(AMI, user data, 보안 그룹) 실행 중인 호스트도 교체한다.
  # 한 대면 교체 중 중단되고, 두 대면 한 대를 유지하며 교체한다.
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = var.host_count == 1 ? 0 : 50
    }
  }

  dynamic "tag" {
    for_each = merge(var.tags, { Name = "${var.name_prefix}-ecs-host" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

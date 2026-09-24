# 단일 AZ의 ECS 호스트다. NAT와 ALB 없이 ECR·SSM에 나가야 하므로 공개 서브넷에
# 명시적으로 IPv4를 할당한다. 보안 그룹은 WireGuard UDP만 공개한다.
# ECS 권장 AMI의 SSM 동적 참조는 Launch Template 생성자에게 ssm:GetParameters를
# 요구한다. 공통 apply 역할의 IAM을 늘리지 않도록 EC2 이미지 조회로 ARM64 ECS AMI를 찾는다.
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
    http_tokens = "required"
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

  # 서버 개인 키는 인스턴스에서 생성해 EBS에만 둔다. user data와 Terraform state에는
  # 개인 키나 클라이언트 설정을 넣지 않는다. 호스트 교체 시 client peer를 다시 등록한다.
  user_data = base64encode(<<-EOT
    #!/bin/bash
    set -euo pipefail
    echo 'ECS_CLUSTER=${var.cluster_name}' >> /etc/ecs/ecs.config
    dnf install -y wireguard-tools
    install -d -m 0700 /etc/wireguard
    wg genkey > /etc/wireguard/server.key
    chmod 0600 /etc/wireguard/server.key
    wg pubkey < /etc/wireguard/server.key > /etc/wireguard/server.pub
    cat > /etc/wireguard/wg0.conf <<EOF
    [Interface]
    Address = 10.62.0.1/24
    ListenPort = 51820
    PrivateKey = $(cat /etc/wireguard/server.key)
    EOF
    chmod 0600 /etc/wireguard/wg0.conf
    systemctl enable --now wg-quick@wg0
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
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = [var.public_subnet_id]

  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
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

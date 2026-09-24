# preprod의 AWS Client VPN이다. 클라이언트와 서버 인증서는 같은 로컬 CA에서
# 발급하고, 서버 인증서만 ACM에 가져온다. 개인 키는 Terraform state에 넣지 않는다.
# 엔드포인트는 연결자가 없어도 시간당 과금되므로 단일 서브넷만 연결한다.
# 앱 접근은 보안 그룹의 TCP 3000으로 제한한다.
resource "aws_cloudwatch_log_group" "connections" {
  name              = "${var.name_prefix}-client-vpn"
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_ec2_client_vpn_endpoint" "this" {
  description            = "${var.name_prefix} certificate-authenticated Client VPN"
  server_certificate_arn = var.server_certificate_arn
  client_cidr_block      = "10.63.0.0/22"
  vpc_id                 = var.vpc_id
  security_group_ids     = [var.security_group_id]
  split_tunnel           = true
  transport_protocol     = "udp"
  vpn_port               = 443

  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = var.server_certificate_arn
  }

  connection_log_options {
    enabled              = true
    cloudwatch_log_group = aws_cloudwatch_log_group.connections.name
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-client-vpn" })
}

resource "aws_ec2_client_vpn_network_association" "this" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  subnet_id              = var.subnet_id
}

resource "aws_ec2_client_vpn_authorization_rule" "vpc" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  target_network_cidr    = var.vpc_cidr
  authorize_all_groups   = true
  description            = "Certificate holders; security groups limit access to the web port"

  depends_on = [aws_ec2_client_vpn_network_association.this]
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["preprod", "prod"], var.environment)
    error_message = "environment는 preprod 또는 prod여야 합니다."
  }
}

variable "availability_zones" {
  type = list(string)
}

locals {
  name_prefix = "aws-fullstack-lab-${var.environment}"
  vpc_cidr    = var.environment == "preprod" ? "10.60.0.0/16" : "10.61.0.0/16"

  public_subnets = {
    for index, az in var.availability_zones : az => cidrsubnet(local.vpc_cidr, 8, index)
  }
  private_subnets = {
    for index, az in var.availability_zones : az => cidrsubnet(local.vpc_cidr, 8, index + 10)
  }

  # 태그는 provider default_tags 대신 각 리소스에 명시한다. Environment 태그는 적용
  # 역할의 권한 조건이므로 모든 리소스에 빠짐없이 있어야 한다.
  tags = {
    Project     = "aws-fullstack-lab"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

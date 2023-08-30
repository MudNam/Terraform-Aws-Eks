module "vpc_eks" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.1"

  name = var.name_prefix

  azs = var.availability_zones

  cidr            = var.vpc_cidr
  private_subnets = var.private_subnets_cidrs
  public_subnets  = var.public_subnets_cidrs

  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  enable_vpn_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  propagate_private_route_tables_vgw = true
  propagate_public_route_tables_vgw  = true

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1",
    "mapPublicIpOnLaunch"             = "FALSE"
    "karpenter.sh/discovery"          = local.eks_cluster_name
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1",
    "mapPublicIpOnLaunch"    = "TRUE"
  }

  tags = {
    "kubernetes.io/cluster/${local.eks_cluster_name}" = "shared"
  }
}

resource "aws_vpc_endpoint" "eks_vpc_ecr_dkr" {
  vpc_id            = module.vpc_eks.vpc_id
  service_name      = data.aws_vpc_endpoint_service.ecr_dkr.service_name
  vpc_endpoint_type = "Interface"

  security_group_ids  = [aws_security_group.eks_vpc_endpoint.id]
  subnet_ids          = module.vpc_eks.private_subnets
  private_dns_enabled = false

  tags = {
    Name = "${local.name_prefix_platform_vpc}-ecr-dkr-${local.environment}"
  }
}

resource "aws_vpc_endpoint" "eks_vpc_sts" {
  vpc_id            = module.vpc_eks.vpc_id
  service_name      = data.aws_vpc_endpoint_service.sts.service_name
  vpc_endpoint_type = "Interface"

  security_group_ids  = [aws_security_group.eks_vpc_endpoint.id]
  subnet_ids          = module.vpc_eks.private_subnets
  private_dns_enabled = false

  tags = {
    Name = "${local.name_prefix_platform_vpc}-sts-${local.environment}"
  }
}

resource "aws_vpc_endpoint" "eks_vpc_s3" {
  vpc_id            = module.vpc_eks.vpc_id
  service_name      = data.aws_vpc_endpoint_service.s3.service_name
  vpc_endpoint_type = "Interface"

  security_group_ids  = [aws_security_group.eks_vpc_endpoint.id]
  subnet_ids          = module.vpc_eks.private_subnets
  private_dns_enabled = false

  tags = {
    Name = "${local.name_prefix_platform_vpc}-s3-${local.environment}"
  }
}

resource "aws_vpc_endpoint" "eks_vpc_aps_workspaces" {
  vpc_id            = module.vpc_eks.vpc_id
  service_name      = data.aws_vpc_endpoint_service.aps_workspaces.service_name
  vpc_endpoint_type = "Interface"

  security_group_ids  = [aws_security_group.eks_vpc_endpoint.id]
  subnet_ids          = module.vpc_eks.private_subnets
  private_dns_enabled = false

  policy = data.aws_iam_policy_document.eks_vpc_aps_workspaces.json

  tags = {
    Name = "${local.name_prefix_platform_vpc}-aps-workspaces-${local.environment}"
  }
}

resource "aws_security_group" "eks_vpc_endpoint" {
  name_prefix = "${var.name_prefix}-vpc-endpoint-sg-"
  description = "Security Group used by VPC Endpoints."
  vpc_id      = module.vpc_eks.vpc_id

  tags = {
    "Name" = "${var.name_prefix}-vpc-endpoint-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "eks_vpc_endpoint_egress" {
  description       = "Allow all egress."
  security_group_id = aws_security_group.eks_vpc_endpoint.id
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "eks_vpc_endpoint_self_ingress" {
  description              = "Self-ingress for all ports."
  security_group_id        = aws_security_group.eks_vpc_endpoint.id
  type                     = "ingress"
  protocol                 = "-1"
  from_port                = 0
  to_port                  = 0
  source_security_group_id = aws_security_group.eks_vpc_endpoint.id
}

resource "aws_vpc_endpoint" "eks_vpc_guardduty" {
  vpc_id            = module.vpc_eks.vpc_id
  service_name      = data.aws_vpc_endpoint_service.guardduty.service_name
  vpc_endpoint_type = "Interface"

  policy = data.aws_iam_policy_document.eks_vpc_guardduty.json

  security_group_ids  = [aws_security_group.eks_vpc_endpoint_guardduty.id]
  subnet_ids          = module.vpc_eks.private_subnets
  private_dns_enabled = true
}

resource "aws_security_group" "eks_vpc_endpoint_guardduty" {
  name_prefix = "${var.name_prefix}-vpc-endpoint-guardduty-sg-"
  description = "Security Group used by VPC Endpoints."
  vpc_id      = module.vpc_eks.vpc_id

  tags = {
    "Name"             = "${var.name_prefix}-vpc-endpoint-guardduty-sg"
    "GuardDutyManaged" = "false"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "eks_vpc_guardduty" {
  security_group_id = aws_security_group.eks_vpc_endpoint_guardduty.id
  description       = "Ingress for port 443."

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  ip_protocol = "tcp"
  to_port     = 443
}

#####
# VPC Flow logs
#####
module "eks_vpc_flow_logs" {
  source  = "native-cube/vpc-flow-logs/aws"
  version = "~> 2.1.0"

  name_prefix = "${var.name_prefix}-vpc-"

  cloudwatch_log_group_name = "/vpc-flow-logs/${var.name_prefix}"

  vpc_id = module.vpc_eks.vpc_id

  retention_in_days = 30

  traffic_type = "ALL"
}

#####
# Outputs
#####
output "vpc_id" {
  value = module.vpc_eks.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc_eks.public_subnets
}

output "private_subnet_ids" {
  value = module.vpc_eks.private_subnets
}

output "private_route_table_ids" {
  value = module.vpc_eks.private_route_table_ids
}

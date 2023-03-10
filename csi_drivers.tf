resource "aws_efs_file_system" "eks" {
  creation_token = module.eks.cluster_name

  tags = {
    Name = module.eks.cluster_name
  }
}

resource "aws_security_group" "efs_eks" {
  name        = "efs-devops-stack"
  description = "Security group for EFS"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }
}

resource "aws_efs_mount_target" "eks" {
  count = length(local.vpc_private_subnets)

  file_system_id  = resource.aws_efs_file_system.eks.id
  subnet_id       = element(module.vpc.private_subnets, count.index)
  security_groups = [resource.aws_security_group.efs_eks.id]
}

module "efs" {
  source = "git::https://github.com/camptocamp/devops-stack-module-efs-csi-driver.git?ref=v1.0.0"

  cluster_name            = local.cluster_name
  argocd_namespace        = module.argocd_bootstrap.argocd_namespace
  efs_file_system_id      = resource.aws_efs_file_system.eks.id
  create_role             = true
  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url
  # iam_role_arn = module.iam_assumable_role_efs.iam_role_arn

  depends_on = [module.argocd_bootstrap]
}

module "ebs" {
  source = "git::https://github.com/camptocamp/devops-stack-module-ebs-csi-driver.git?ref=v1.0.0"

  cluster_name            = local.cluster_name
  argocd_namespace        = module.argocd_bootstrap.argocd_namespace
  create_role             = true
  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url
  # iam_role_arn = module.iam_assumable_role_ebs.iam_role_arn

  depends_on = [module.argocd_bootstrap]
}

# module "iam_assumable_role_ebs" {
#   source                     = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
#   version                    = "~> 5.0"
#   create_role                = true
#   number_of_role_policy_arns = 1
#   role_name                  = format("ebs-csi-driver-%s", local.cluster_name)
#   provider_url               = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
#   role_policy_arns           = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"] # Use the default IAM policy provided by AWS

#   # List of ServiceAccounts that have permission to attach to this IAM role
#   oidc_fully_qualified_subjects = [
#     "system:serviceaccount:kube-system:ebs-csi-controller-sa",
#   ]
# }

# resource "aws_iam_policy" "efs" {
#   name_prefix = "efs-csi-driver-"

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "elasticfilesystem:DescribeAccessPoints",
#           "elasticfilesystem:DescribeFileSystems",
#           "elasticfilesystem:DescribeMountTargets",
#           "ec2:DescribeAvailabilityZones"
#         ]
#         Resource = "*"
#       },
#       {
#         Effect = "Allow"
#         Action = [
#           "elasticfilesystem:CreateAccessPoint"
#         ]
#         Resource = "*"
#         Condition = {
#           StringLike = {
#             "aws:RequestTag/efs.csi.aws.com/cluster" = "true"
#           }
#         }
#       },
#       {
#         Effect   = "Allow"
#         Action   = "elasticfilesystem:DeleteAccessPoint"
#         Resource = "*"
#         Condition = {
#           StringEquals = {
#             "aws:ResourceTag/efs.csi.aws.com/cluster" = "true"
#           }
#         }
#       }
#     ]
#   })
# }

# module "iam_assumable_role_efs" {
#   source                     = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
#   version                    = "~> 5.0"
#   create_role                = true
#   number_of_role_policy_arns = 1
#   role_name                  = format("efs-csi-driver-%s", local.cluster_name)
#   provider_url               = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
#   role_policy_arns           = [resource.aws_iam_policy.efs.arn]

#   # List of ServiceAccounts that have permission to attach to this IAM role
#   oidc_fully_qualified_subjects = [
#     "system:serviceaccount:kube-system:efs-csi-controller-sa",
#   ]
# }


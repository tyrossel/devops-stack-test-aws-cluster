resource "aws_s3_bucket" "velero_backup_storage" {
  bucket = format("velero-backup-storage-%s", module.eks.cluster_name)

  force_destroy = true

  tags = {
    Description = "Velero backup storage"
    Cluster     = module.eks.cluster_name
  }
}

module "iam_assumable_role_velero" {
  source                     = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version                    = "~> 5.0"
  create_role                = true
  number_of_role_policy_arns = 1
  role_name_prefix           = format("velero-s3-%s-", local.cluster_name)
  provider_url               = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
  role_policy_arns           = [resource.aws_iam_policy.velero_s3_policy.arn]

  # List of ServiceAccounts that have permission to attach to this IAM role
  oidc_fully_qualified_subjects = [
    format("system:serviceaccount:velero:velero-server")
  ]
}

resource "aws_iam_policy" "velero_s3_policy" {
  name_prefix = "velero-s3-"
  description = "Velero IAM policy for cluster ${module.eks.cluster_name}"
  policy      = data.aws_iam_policy_document.velero_s3_policy.json
}

data "aws_iam_policy_document" "velero_s3_policy" {
  statement {
    actions = [
      "s3:ListBucket",
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
    ]

    resources = [
      aws_s3_bucket.velero_backup_storage.arn,
      format("%s/*", aws_s3_bucket.velero_backup_storage.arn),
    ]

    effect = "Allow"
  }

  statement {
    actions = [
      "ec2:DescribeVolumes",
      "ec2:DescribeSnapshots",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot"
    ]
	resources = ["*"]
	effect = "Allow"
  }
}

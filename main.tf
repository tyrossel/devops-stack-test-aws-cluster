# Providers configuration

# These providers depend on the output of the respectives modules declared below.
# However, for clarity and ease of maintenance we grouped them all together in this section.

provider "kubernetes" {
  host                   = module.eks.kubernetes_host
  cluster_ca_certificate = module.eks.kubernetes_cluster_ca_certificate
  token                  = module.eks.kubernetes_token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.kubernetes_host
    cluster_ca_certificate = module.eks.kubernetes_cluster_ca_certificate
    token                  = module.eks.kubernetes_token
  }
}

provider "argocd" {
  server_addr                 = "127.0.0.1:8080"
  auth_token                  = module.argocd_bootstrap.argocd_auth_token
  insecure                    = true
  plain_text                  = true
  port_forward                = true
  port_forward_with_namespace = module.argocd_bootstrap.argocd_namespace

  kubernetes {
    host                   = module.eks.kubernetes_host
    cluster_ca_certificate = module.eks.kubernetes_cluster_ca_certificate
    token                  = module.eks.kubernetes_token
  }
}

###

# Module declarations and configuration

data "aws_availability_zones" "available" {}

module "vpc" {
  source               = "terraform-aws-modules/vpc/aws"
  version              = "~> 3.0"
  name                 = module.eks.cluster_name
  cidr                 = local.vpc_cidr
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = local.vpc_private_subnets
  public_subnets       = local.vpc_public_subnets
  enable_nat_gateway   = true
  create_igw           = true
  enable_dns_hostnames = true

  private_subnet_tags = {
    "kubernetes.io/cluster/${module.eks.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"                  = "1"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${module.eks.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                           = "1"
  }
}

module "eks" {
  source = "git::https://github.com/camptocamp/devops-stack-module-cluster-eks?ref=v2.0.1"

  cluster_name       = local.cluster_name
  kubernetes_version = local.cluster_version
  base_domain        = local.base_domain

  vpc_id = module.vpc.vpc_id

  private_subnet_ids = module.vpc.private_subnets
  public_subnet_ids  = module.vpc.public_subnets

  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]

  node_groups = {
    "${module.eks.cluster_name}-main" = {
      instance_type     = "m5a.large"
      min_size          = 2
      max_size          = 3
      desired_size      = 2
      target_group_arns = module.eks.nlb_target_groups
    },
  }

  create_public_nlb = true
}

module "oidc" {
  source = "git::https://github.com/camptocamp/devops-stack-module-oidc-aws-cognito.git?ref=v1.0.0"

  cluster_name = module.eks.cluster_name
  base_domain  = module.eks.base_domain

  create_pool = true

  user_map = {
    trossel = {
      username    = "trossel"
      email       = "tanguy.rossel@camptocamp.com"
      given_name  = "Tanguy"
      family_name = "Rossel"
    }
  }
}

module "argocd_bootstrap" {
  source = "git::https://github.com/camptocamp/devops-stack-module-argocd.git//bootstrap?ref=v2.1.0"

  depends_on = [module.eks]
}

module "traefik" {
  source = "git::https://github.com/camptocamp/devops-stack-module-traefik.git//eks?ref=v1.2.3"

  cluster_name     = module.eks.cluster_name
  base_domain      = module.eks.base_domain
  argocd_namespace = module.argocd_bootstrap.argocd_namespace

  enable_service_monitor = local.enable_service_monitor

  dependency_ids = {
    argocd = module.argocd_bootstrap.id
  }
}


module "cert-manager" {
  source = "git::https://github.com/camptocamp/devops-stack-module-cert-manager.git//eks?ref=v4.0.3"

  cluster_name     = module.eks.cluster_name
  base_domain      = module.eks.base_domain
  argocd_namespace = module.argocd_bootstrap.argocd_namespace

  enable_service_monitor = local.enable_service_monitor

  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url

  dependency_ids = {
    argocd = module.argocd_bootstrap.id
  }
}

# module "loki-stack" {
#   source = "git::https://github.com/camptocamp/devops-stack-module-loki-stack//eks?ref=v2.0.2"
#
#   argocd_namespace = module.argocd_bootstrap.argocd_namespace
#
#   distributed_mode = true
#
#   logs_storage = {
#     bucket_id    = aws_s3_bucket.loki_logs_storage.id
#     region       = aws_s3_bucket.loki_logs_storage.region
#     iam_role_arn = module.iam_assumable_role_loki.iam_role_arn
#   }
#
#   dependency_ids = {
#     argocd = module.argocd_bootstrap.id
#   }
# }

# module "thanos" {
#   source = "git::https://github.com/camptocamp/devops-stack-module-thanos.git//eks?ref=v1.0.0"
#
#   cluster_name     = module.eks.cluster_name
#   base_domain      = module.eks.base_domain
#   cluster_issuer   = local.cluster_issuer
#   argocd_namespace = module.argocd_bootstrap.argocd_namespace
#
#   metrics_storage = {
#     bucket_id    = aws_s3_bucket.thanos_metrics_storage.id
#     region       = aws_s3_bucket.thanos_metrics_storage.region
#     iam_role_arn = module.iam_assumable_role_thanos.iam_role_arn
#   }
#   thanos = {
#     oidc = module.oidc.oidc
#   }
#
#   dependency_ids = {
#     argocd       = module.argocd_bootstrap.id
#     traefik      = module.traefik.id
#     cert-manager = module.cert-manager.id
#     oidc         = module.oidc.id
#   }
# }

module "kube-prometheus-stack" {
  source = "git::https://github.com/camptocamp/devops-stack-module-kube-prometheus-stack.git//eks?ref=v3.2.0"

  cluster_name     = module.eks.cluster_name
  argocd_namespace = module.argocd_bootstrap.argocd_namespace
  base_domain      = module.eks.base_domain
  cluster_issuer   = local.cluster_issuer

  # metrics_storage = {
  #   bucket_id    = aws_s3_bucket.thanos_metrics_storage.id
  #   region       = aws_s3_bucket.thanos_metrics_storage.region
  #   iam_role_arn = module.iam_assumable_role_thanos.iam_role_arn
  # }

  prometheus = {
    oidc = module.oidc.oidc
  }

  alertmanager = {
    oidc = module.oidc.oidc
  }

  grafana = {
    oidc = module.oidc.oidc
  }

  dependency_ids = {
    argocd       = module.argocd_bootstrap.id
    traefik      = module.traefik.id
    cert-manager = module.cert-manager.id
    oidc         = module.oidc.id
    # thanos       = module.thanos.id
  }
}

module "backup" {
  # source           = "git::https://github.com/camptocamp/devops-stack-module-backup.git//eks?ref=grafana"
  source           = "../module-backup/eks"
  target_revision  = "grafana"
  cluster_name     = local.cluster_name
  base_domain      = local.base_domain
  argocd_namespace = module.argocd_bootstrap.argocd_namespace

  enable_monitoring_dashboard = true

  backup_schedules = {
    snapshot-backup = {
      disabled = false
      schedule = "* 4 * * *"
      template = {
        # storageLocation    = "backup-bucket"
        includedNamespaces = ["wordpress"]
        includedResources  = ["persistentVolumes", "persistentVolumeClaims"]
      }
    },
    restic-backup = {
      disabled = false
      schedule = "* 4 * * *"
      template = {
        # storageLocation    = "backup-bucket"
        includedNamespaces = ["wordpress", "velero"]
        includedResources  = ["persistentVolumes", "persistentVolumeClaims", "pods"]
      }
    }
  }

  default_backup_storage = {
    bucket_id    = aws_s3_bucket.velero_backup_storage.id
    region       = aws_s3_bucket.velero_backup_storage.region
    iam_role_arn = module.iam_assumable_role_velero.iam_role_arn
  }


  dependency_ids = {
    kube-prometheus-stack = module.kube-prometheus-stack.id,
    argocd                = module.argocd_bootstrap.id # TODO Can cause issues on the first cluster bootstrap. If it's the case, deploy after the last argocd.
  }
}

module "argocd" {
  source = "git::https://github.com/camptocamp/devops-stack-module-argocd.git?ref=v2.1.0"

  cluster_name   = module.eks.cluster_name
  base_domain    = module.eks.base_domain
  cluster_issuer = local.cluster_issuer

  admin_enabled            = "true"
  namespace                = module.argocd_bootstrap.argocd_namespace
  accounts_pipeline_tokens = module.argocd_bootstrap.argocd_accounts_pipeline_tokens
  server_secretkey         = module.argocd_bootstrap.argocd_server_secretkey

  oidc = {
    name         = "OIDC"
    issuer       = module.oidc.oidc.issuer_url
    clientID     = module.oidc.oidc.client_id
    clientSecret = module.oidc.oidc.client_secret
    requestedIDTokenClaims = {
      groups = {
        essential = true
      }
    }
    requestedScopes = [
      "openid", "profile", "email"
    ]
  }

  dependency_ids = {
    argocd                = module.argocd_bootstrap.id
    traefik               = module.traefik.id
    cert-manager          = module.cert-manager.id
    oidc                  = module.oidc.id
    kube-prometheus-stack = module.kube-prometheus-stack.id
  }
}

module "metrics_server" {
  source = "git::https://github.com/camptocamp/devops-stack-module-application.git?ref=v1.2.2"

  name             = "metrics-server"
  argocd_namespace = module.argocd_bootstrap.argocd_namespace

  source_repo            = "https://github.com/kubernetes-sigs/metrics-server.git"
  source_repo_path       = "charts/metrics-server"
  source_target_revision = "metrics-server-helm-chart-3.8.3"
  destination_namespace  = "kube-system"

  dependency_ids = {
    argocd = module.argocd.id
  }
}

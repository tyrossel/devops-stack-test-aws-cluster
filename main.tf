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
  source = "git::https://github.com/camptocamp/devops-stack-module-cluster-eks?ref=v1.0.0-alpha.2"

  cluster_name       = local.cluster_name
  kubernetes_version = local.cluster_version
  base_domain        = local.base_domain

  vpc_id         = module.vpc.vpc_id
  vpc_cidr_block = module.vpc.vpc_cidr_block

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
  # source = "git::https://github.com/camptocamp/devops-stack-module-oidc-aws-cognito.git?ref=v1.0.0-alpha.1"
  source = "git::https://github.com/camptocamp/devops-stack-module-oidc-aws-cognito.git?ref=fix_and_improvements"

  cluster_name = module.eks.cluster_name
  base_domain  = module.eks.base_domain

  create_pool = true

  user_map = {
    gheleno = {
      username    = "gheleno"
      email       = "goncalo.heleno@camptocamp.com"
      given_name  = "Gonçalo"
      family_name = "Heleno"
    }
  }
}

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

module "argocd_bootstrap" {
  source = "git::https://github.com/camptocamp/devops-stack-module-argocd.git//bootstrap?ref=v1.0.0-alpha.7"

  depends_on = [module.eks]
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

module "ingress" {
  source = "git::https://github.com/camptocamp/devops-stack-module-traefik.git//eks?ref=v1.0.0-alpha.8"

  cluster_name     = module.eks.cluster_name
  argocd_namespace = module.argocd_bootstrap.argocd_namespace
  base_domain      = module.eks.base_domain

  depends_on = [module.argocd_bootstrap]
}

module "thanos" {
  source = "git::https://github.com/camptocamp/devops-stack-module-thanos.git//eks?ref=v1.0.0-alpha.8"

  cluster_name     = module.eks.cluster_name
  argocd_namespace = module.argocd_bootstrap.argocd_namespace
  base_domain      = module.eks.base_domain
  cluster_issuer   = local.cluster_issuer

  metrics_storage = {
    bucket_id    = aws_s3_bucket.thanos_metrics_storage.id
    region       = aws_s3_bucket.thanos_metrics_storage.region
    iam_role_arn = module.iam_assumable_role_thanos.iam_role_arn
  }
  thanos = {
    oidc = module.oidc.oidc
  }

  depends_on = [module.argocd_bootstrap]
}

module "prometheus-stack" {
  source = "git::https://github.com/camptocamp/devops-stack-module-kube-prometheus-stack.git//eks?ref=v1.0.0-alpha.6"

  cluster_name     = module.eks.cluster_name
  argocd_namespace = module.argocd_bootstrap.argocd_namespace
  base_domain      = module.eks.base_domain
  cluster_issuer   = local.cluster_issuer

  metrics_storage = {
    bucket_id    = aws_s3_bucket.thanos_metrics_storage.id
    region       = aws_s3_bucket.thanos_metrics_storage.region
    iam_role_arn = module.iam_assumable_role_thanos.iam_role_arn
  }

  prometheus = {
    oidc = module.oidc.oidc
  }
  alertmanager = {
    oidc = module.oidc.oidc
  }
  grafana = {
    # enable = false # Optional
    additional_data_sources = true
  }

  depends_on = [module.argocd_bootstrap, module.thanos]
}

module "loki-stack" {
  source = "git::https://github.com/camptocamp/devops-stack-module-loki-stack//eks?ref=v1.0.0-alpha.13"

  cluster_name     = module.eks.cluster_name
  argocd_namespace = module.argocd_bootstrap.argocd_namespace
  base_domain      = module.eks.base_domain

  distributed_mode = true

  logs_storage = {
    bucket_id    = aws_s3_bucket.loki_logs_storage.id
    region       = aws_s3_bucket.loki_logs_storage.region
    iam_role_arn = module.iam_assumable_role_loki.iam_role_arn
  }

  depends_on = [module.prometheus-stack]
}

module "grafana" {
  source = "git::https://github.com/camptocamp/devops-stack-module-grafana.git?ref=v1.0.0-alpha.4"

  cluster_name     = module.eks.cluster_name
  argocd_namespace = module.argocd_bootstrap.argocd_namespace
  base_domain      = module.eks.base_domain
  cluster_issuer   = local.cluster_issuer

  grafana = {
    oidc = module.oidc.oidc
  }

  depends_on = [module.prometheus-stack, module.loki-stack]
}

module "cert-manager" {
  source = "git::https://github.com/camptocamp/devops-stack-module-cert-manager.git//eks?ref=v1.0.0-alpha.6"

  cluster_name     = module.eks.cluster_name
  argocd_namespace = module.argocd_bootstrap.argocd_namespace
  base_domain      = module.eks.base_domain

  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url

  depends_on = [module.prometheus-stack]
}

module "argocd" {
  source = "git::https://github.com/camptocamp/devops-stack-module-argocd.git?ref=v1.0.0-alpha.7"

  cluster_name   = module.eks.cluster_name
  base_domain    = module.eks.base_domain
  cluster_issuer = local.cluster_issuer

  admin_enabled            = "true" # honors bootstrap's argocd-initial-admin-secret
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

  helm_values = [{
    argo-cd = {
      config = {
        rbac = {
          "scopes"     = "[groups]"
          "policy.csv" = <<-EOT
            g, pipeline, role:admin
            g, devops-stack-admins, role:admin
            EOT
        }
      }
    }
  }]

  depends_on = [module.cert-manager, module.prometheus-stack, module.grafana]
}

module "metrics_server" {
  source = "git::https://github.com/camptocamp/devops-stack-module-application.git?ref=v1.2.2"

  name             = "metrics-server"
  argocd_namespace = module.argocd_bootstrap.argocd_namespace

  source_repo            = "https://github.com/kubernetes-sigs/metrics-server.git"
  source_repo_path       = "charts/metrics-server"
  source_target_revision = "metrics-server-helm-chart-3.8.3"
  destination_namespace  = "kube-system"

  depends_on = [module.argocd]
}

/*
module "helloworld_apps" {
  source = "git::https://github.com/camptocamp/devops-stack-module-applicationset.git?ref=v1.2.3"

  depends_on = [module.argocd]

  name                   = "helloworld-apps"
  argocd_namespace       = module.argocd_bootstrap.argocd_namespace
  project_dest_namespace = "*"
  project_source_repo    = "https://github.com/camptocamp/devops-stack-helloworld-templates.git"

  generators = [
    {
      git = {
        repoURL  = "https://github.com/camptocamp/devops-stack-helloworld-templates.git"
        revision = "main"

        directories = [
          {
            path = "apps/*"
          }
        ]
      }
    }
  ]
  template = {
    metadata = {
      name = "{{path.basename}}"
    }

    spec = {
      project = "helloworld-apps"

      source = {
        repoURL        = "https://github.com/camptocamp/devops-stack-helloworld-templates.git"
        targetRevision = "main"
        path           = "{{path}}"

        helm = {
          valueFiles = []
          # The following value defines this global variables that will be available to all apps in apps/*
          # These are needed to generate the ingresses containing the name and base domain of the cluster.
          values = <<-EOT
            cluster:
              name: "${module.eks.cluster_name}"
              domain: "${module.eks.base_domain}"
              issuer: "${local.cluster_issuer}"
            apps:
              traefik_dashboard: false
              grafana: true
              prometheus: true
              thanos: true
              alertmanager: true
          EOT
        }
      }

      destination = {
        name      = "in-cluster"
        namespace = "{{path.basename}}"
      }

      syncPolicy = {
        automated = {
          allowEmpty = false
          selfHeal   = true
          prune      = true
        }
        syncOptions = [
          "CreateNamespace=true"
        ]
      }
    }
  }
}
*/

# module "private_apps" {
#   source = "../devops-stack-module-applicationset"

#   depends_on = [module.argocd]

#   name                   = "private-apps"
#   argocd_namespace       = module.argocd_bootstrap.argocd_namespace
#   project_dest_namespace = "*"
#   project_source_repo    = "https://github.com/lentidas/devops-stack-private-chart.git"
#   source_credentials_ssh_key = file("${path.module}/id_ed25519_test")

#   generators = [
#     {
#       git = {
#         repoURL  = "https://github.com/lentidas/devops-stack-private-chart.git"
#         revision = "main"

#         directories = [
#           {
#             path = "apps/*"
#           }
#         ]
#       }
#     }
#   ]
#   template = {
#     metadata = {
#       name = "{{path.basename}}"
#     }

#     spec = {
#       project = "private-apps"

#       source = {
#         repoURL        = "https://github.com/lentidas/devops-stack-private-chart.git"
#         targetRevision = "main"
#         path           = "{{path}}"

#         helm = {
#           valueFiles = []
#           # The following value defines this global variables that will be available to all apps in apps/*
#           # These are needed to generate the ingresses containing the name and base domain of the cluster.
#           values = <<-EOT
#             cluster:
#               name: "${module.eks.cluster_name}"
#               domain: "${module.eks.base_domain}"
#           EOT
#         }
#       }

#       destination = {
#         name      = "in-cluster"
#         namespace = "{{path.basename}}"
#       }

#       syncPolicy = {
#         automated = {
#           allowEmpty = false
#           selfHeal   = true
#           prune      = true
#         }
#         syncOptions = [
#           "CreateNamespace=true"
#         ]
#       }
#     }
#   }
# }

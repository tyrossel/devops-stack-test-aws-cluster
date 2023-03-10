locals {
  cluster_name    = "gh-v1-cluster"
  cluster_version = "1.24"
  base_domain     = "is-sandbox.camptocamp.com"

  vpc_cidr            = "10.56.0.0/16"
  vpc_private_subnets = ["10.56.1.0/24", "10.56.2.0/24", "10.56.3.0/24"]
  vpc_public_subnets  = ["10.56.4.0/24", "10.56.5.0/24", "10.56.6.0/24"]


  cluster_issuer = "letsencrypt-staging"

  # argocd_namespace = "argocd" # Argo CD is deployed by default inside the namespace `argocd` but we need to tell this to the other modules.
}

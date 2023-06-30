terraform {
  backend "s3" {
    encrypt        = true
    bucket         = "camptocamp-aws-is-sandbox-terraform-state"
    key            = "5c996b23-ff33-4e22-b29d-f5fdf3b3208f"
    region         = "eu-west-1"
    dynamodb_table = "camptocamp-aws-is-sandbox-terraform-statelock"
  }

  required_providers {
    aws = { # Needed to store the state file in S3
      source  = "hashicorp/aws"
      version = "~> 4"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2"
    }
    argocd = {
      source  = "oboukili/argocd"
      version = "~> 4"
    }
  }
}

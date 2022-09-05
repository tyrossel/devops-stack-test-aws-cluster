terraform {
  backend "s3" {
    encrypt        = true
    bucket         = "camptocamp-aws-is-sandbox-terraform-state"
    key            = "15f7abf9-abb4-4847-b4dc-af71574ebdf0"
    region         = "eu-west-1"
    dynamodb_table = "camptocamp-aws-is-sandbox-terraform-statelock"
  }

  required_providers {
    argocd = {
      source = "oboukili/argocd"
    }
  }
}

# 2 eme solution modifier le code source du provider pour attendre la creation de la resource AppProject

# 3 eme solution utiliser la boucle de app of apps
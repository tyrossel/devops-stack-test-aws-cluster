# devops-stack-test-aws-cluster

Repository that holds the Terraform files for my test cluster on AWS EKS using Camptocamp's [DevOps Stack](https://devops-stack.io/).

```bash
# Create the cluster
summon terraform init && summon terraform apply

# Get the kubeconfig settings for the created cluster
summon aws eks update-kubeconfig --name gh-v1-cluster --region eu-west-1

# Destroy the cluster
summon terraform state rm $(summon terraform state list | grep "argocd_application\|argocd_project\|kubernetes_\|helm_") && summon terraform destroy
```

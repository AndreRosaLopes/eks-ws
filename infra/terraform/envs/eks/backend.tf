terraform {
  backend "s3" {
    bucket       = "eks-ws-tfstate-283429977024"
    key          = "terraform/lakehouse_opensource_eks/eks/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

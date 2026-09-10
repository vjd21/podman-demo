# Platform stack: the account-wide IAM and KMS resources the pipelines run on.
# Separate state from the app stack (../) so destroying an EC2 instance can never
# take the CI roles or the signing key with it.
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # >= 5.71 for aws_iam_role_policies_exclusive, which is what
      # detaches AdministratorAccess and keeps it detached.
      version = ">= 5.71, < 6.0"
    }
  }

  backend "s3" {
    bucket       = "aws-terraform-statefiles-bucket"
    key          = "dev/podman-demo/platform.tfstate"
    region       = "us-east-2"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region
}

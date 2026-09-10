# Platform stack: the account-wide IAM, KMS and S3 resources the pipelines run on.
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

  default_tags {
    tags = {
      Project   = "podman-demo"
      ManagedBy = "terraform"
    }
  }
}

# Asked of AWS rather than written down. The account id in particular appeared
# in five places across this repo; none of them can now drift.
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

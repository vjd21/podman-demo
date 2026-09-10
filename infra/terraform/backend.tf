terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.71, < 6.0"
    }
  }

  # key is supplied per environment by the infra pipeline:
  #   -backend-config="key=dev/podman-demo/<environment>/infra.tfstate"
  # so dev and any later environment never share state. The dev/podman-demo/
  # prefix is fixed: infra-provision-role's S3 grant is scoped to exactly that,
  # so a key outside it fails init with a 403 on HeadObject.
  backend "s3" {
    bucket       = "aws-terraform-statefiles-bucket"
    region       = "us-east-2"
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-2"
}

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.71, < 6.0"
    }
  }

  # key is supplied per environment by the infra pipeline:
  #   -backend-config="key=podman-demo/<environment>/infra.tfstate"
  # so dev and any later environment never share state.
  backend "s3" {
    bucket       = "aws-terraform-statefiles-bucket"
    region       = "us-east-2"
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-2"
}

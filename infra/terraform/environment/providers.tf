terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.71, < 6.0"
    }
  }

  # key is supplied per environment by the infrastructure pipeline:
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
  region = var.region

  default_tags {
    tags = {
      Project     = "podman-demo"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Everything below is asked of AWS rather than written down here. An id in a
# variable is a value that has to be kept true by hand; a data source cannot go
# stale. The AMI default that had been deregistered is the cautionary case --
# see docs/issues-and-fixes.md.

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# When the custom-image pipeline does not hand over an AMI -- because it was
# skipped, or the stack is applied on its own -- fall back to the most recent
# image Packer baked, rather than to a hardcoded id.
data "aws_ami" "custom" {
  count = var.ami_id == "" ? 1 : 0

  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["podman-demo-host-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

locals {
  ami_id    = var.ami_id != "" ? var.ami_id : data.aws_ami.custom[0].id
  subnet_id = var.subnet_id != "" ? var.subnet_id : sort(data.aws_subnets.default.ids)[0]

  env_file = "${path.module}/../../../envs/${var.environment}.yaml"
  tenants  = yamldecode(file(local.env_file)).tenants

  # Instances are named <environment>-<tenant>. That name is the EC2 Name tag,
  # which is what the deploy inventory filters on.
  names = { for id, cfg in local.tenants : id => "${var.environment}-${id}" }
}

variable "region" {
  description = "AWS region for every resource in this stack."
  type        = string
  default     = "us-east-2"
}

variable "account_id" {
  description = "AWS account id. Only used to build ARNs."
  type        = string
  default     = "148737623247"
}

variable "github_repo" {
  description = "owner/name of the only repository allowed to assume the CI roles."
  type        = string
  default     = "vjd21/podman-demo"
}

variable "deploy_ref" {
  description = <<-EOT
    The single git ref allowed to assume the CI roles. Deploys are pinned to main
    because the Quadlet unit's keyless cosign verify also pins
    .github/workflows/deploy.yml@refs/heads/main -- a deploy from any other branch
    would fail that check anyway.
  EOT
  type        = string
  default     = "refs/heads/main"
}

variable "ssm_transfer_bucket" {
  description = "Existing S3 bucket the Ansible aws_ssm connection plugin uses to move files to the host."
  type        = string
  default     = "sriharis3bucket"
}

variable "state_bucket" {
  description = "Existing S3 bucket holding Terraform remote state."
  type        = string
  default     = "aws-terraform-statefiles-bucket"
}

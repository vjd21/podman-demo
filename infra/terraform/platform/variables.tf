variable "region" {
  description = "AWS region for every resource in this stack."
  type        = string
  default     = "us-east-2"
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

variable "state_bucket" {
  description = "Existing S3 bucket holding Terraform remote state."
  type        = string
  default     = "aws-terraform-statefiles-bucket"
}

variable "github_owner_id" {
  description = <<-EOT
    Numeric GitHub owner id. This organisation issues OIDC tokens using the
    immutable-id subject format (owner@ownerID/repo@repoID), so the trust policy
    must match that literal string as well as the human-readable one. Verified
    against the sub claim CloudTrail recorded on a real AssumeRoleWithWebIdentity
    attempt -- do not guess it.
  EOT
  type        = string
  default     = "112800271"
}

variable "github_repo_id" {
  description = "Numeric GitHub repository id. See github_owner_id."
  type        = string
  default     = "1356067443"
}

variable "environment" {
  description = "Environment name. Selects envs/<environment>.yaml and the Terraform state key."
  type        = string
  default     = "dev"
}

variable "region" {
  description = "Region to operate in."
  type        = string
  default     = "us-east-2"
}

variable "ami_id" {
  description = <<-EOT
    AMI to launch, from the custom-image pipeline. Leave empty to use the most
    recent podman-demo-host-* image this account owns. Empty is the default on
    purpose -- a pinned id silently rots when the image is deregistered.
  EOT
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = <<-EOT
    Subnet to launch into. Leave empty to use the default subnet of the default
    VPC, which is where these hosts already live. Set it only when a specific
    subnet is required.
  EOT
  type        = string
  default     = ""
}

variable "default_instance_type" {
  description = "Instance type for tenants that do not set one."
  type        = string
  default     = "t3.micro"
}

variable "iam_instance_profile" {
  description = <<-EOT
    IAM instance profile to attach. Created by the platform stack and carries
    only AmazonSSMManagedInstanceCore plus S3 access to the SSM transfer bucket.
    The previous default was "admin", whose role held AdministratorAccess -- a
    container escape on the host was full account compromise.
  EOT
  type        = string
  default     = "podman-demo-host"
}

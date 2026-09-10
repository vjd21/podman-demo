variable "environment" {
  description = "Environment name. Selects envs/<environment>.yaml and the Terraform state key."
  type        = string
  default     = "dev"
}

variable "ami_id" {
  description = "AMI to launch -- the output of the custom-image pipeline."
  type        = string
  default     = "ami-04afd14ab83ca1834"
}

variable "default_instance_type" {
  description = "Instance type for tenants that do not set one."
  type        = string
  default     = "t3.micro"
}

variable "subnet_id" {
  description = "Subnet to launch into."
  type        = string
  default     = "subnet-06b6ab6f608584887"
}

variable "iam_instance_profile" {
  description = <<-EOT
    IAM instance profile to attach. Created by the platform stack
    (infra/terraform/platform) and carries only AmazonSSMManagedInstanceCore. The
    previous default was "admin", whose role held AdministratorAccess -- a
    container escape on the host was full account compromise.
  EOT
  type        = string
  default     = "podman-demo-host"
}

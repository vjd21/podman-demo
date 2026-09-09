variable "instance_name" {
  description = "Value for the EC2 instance's Name tag -- also used by deploy/ansible/aws_ec2.yml's dynamic inventory filter to target this instance for deploys."
  type        = string
}

variable "ami_id" {
  description = "AMI to launch, e.g. the output of the Packer build workflow. Defaults to the AMI currently running on e1087 if not supplied."
  type        = string
  default     = "ami-04afd14ab83ca1834"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "subnet_id" {
  description = "Subnet to launch into -- reuses the same subnet as the existing e1087 instance."
  type        = string
  default     = "subnet-06b6ab6f608584887"
}

variable "security_group_id" {
  description = "Security group to attach -- reuses the same one as the existing e1087 instance (sg-08000f3eb1834032d)."
  type        = string
  default     = "sg-08000f3eb1834032d"
}

variable "iam_instance_profile" {
  description = "IAM instance profile to attach -- reuses the same one as the existing e1087 instance."
  type        = string
  default     = "admin"
}

variable "key_name" {
  description = "SSH key pair name -- not required for deploys (Ansible connects via SSM), kept only for parity/manual debugging access matching e1087."
  type        = string
  default     = "vkey"
}

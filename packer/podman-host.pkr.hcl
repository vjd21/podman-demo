packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-2"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "subnet_id" {
  description = "Subnet to build in -- reuses the same one the running e1087 instance uses."
  type        = string
  default     = "subnet-06b6ab6f608584887"
}

variable "security_group_id" {
  description = "Security group for the temporary build instance -- reuses the same one e1087 uses (already allows inbound SSH)."
  type        = string
  default     = "sg-08000f3eb1834032d"
}

source "amazon-ebs" "podman_host" {
  region                      = var.region
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  security_group_id           = var.security_group_id
  associate_public_ip_address = true
  ssh_username                = "ubuntu"
  ami_name                    = "podman-demo-host-{{timestamp}}"
  ami_description             = "Golden AMI: podman + cosign + podman-demo policy config pre-installed"

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-resolute-26.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"] # Canonical
  }
}

build {
  name    = "podman-host"
  sources = ["source.amazon-ebs.podman_host"]

  provisioner "file" {
    source      = "../server-config/policy.json"
    destination = "/tmp/policy.json"
  }

  provisioner "file" {
    source      = "../server-config/setup.sh"
    destination = "/tmp/setup.sh"
  }

  provisioner "shell" {
    inline = [
      "sudo mkdir -p /tmp/server-config",
      "sudo mv /tmp/policy.json /tmp/server-config/policy.json",
      "sudo mv /tmp/setup.sh /tmp/server-config/setup.sh",
      "sudo chmod +x /tmp/server-config/setup.sh",
      "cd /tmp/server-config && ./setup.sh",
    ]
  }
}

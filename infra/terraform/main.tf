# When the custom-image pipeline does not hand over an AMI -- because it was
# skipped, or the stack is applied on its own -- fall back to the most recent
# image Packer baked, rather than to a hardcoded id. A pinned default goes stale
# silently: the previous one had been deregistered, and Terraform failed with
# "collecting instance settings: empty result", which names neither the AMI nor
# the fact that it no longer exists.
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
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.custom[0].id

  env_file = "${path.module}/../../envs/${var.environment}.yaml"
  tenants  = yamldecode(file(local.env_file)).tenants

  # Instances are named <environment>-<tenant>. That name is the EC2 Name tag,
  # which is what the deploy inventory filters on.
  names = { for id, cfg in local.tenants : id => "${var.environment}-${id}" }
}

# One security group per tenant, so opening a port for one tenant cannot expose
# another.
resource "aws_security_group" "tenant" {
  for_each = local.tenants

  name        = "podman-demo-${local.names[each.key]}"
  description = "podman-demo ${var.environment}/${each.key}"

  # No SSH rule: Ansible reaches the host over SSM Session Manager.
  ingress {
    description = "Application"
    from_port   = try(each.value.port, 8081)
    to_port     = try(each.value.port, 8081)
    protocol    = "tcp"
    cidr_blocks = try(each.value.allowed_cidrs, ["0.0.0.0/0"])
  }

  egress {
    description = "Outbound for GHCR pulls, SSM and package installs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "podman-demo-${local.names[each.key]}"
  }
}

resource "aws_instance" "host" {
  for_each = local.tenants

  ami                    = local.ami_id
  instance_type          = try(each.value.instance_type, var.default_instance_type)
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.tenant[each.key].id]
  iam_instance_profile   = var.iam_instance_profile

  # No key_name: Ansible reaches the host over SSM Session Manager, so the
  # instance has no SSH key pair and needs no inbound SSH at all.

  # Require IMDSv2. Blocks the SSRF-to-credentials path that makes an
  # over-privileged instance profile so dangerous.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted = true
  }

  tags = {
    Name        = local.names[each.key]
    Environment = var.environment
    Tenant      = each.key
  }

  # Removing a tenant from the environment file must not silently terminate a
  # running host. Deleting one is deliberate: remove this block, then apply.
  lifecycle {
    prevent_destroy = true
  }
}

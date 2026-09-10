# One security group per tenant, so opening a port for one cannot expose another.
resource "aws_security_group" "tenant" {
  for_each = local.tenants

  name        = "podman-demo-${local.names[each.key]}"
  description = "podman-demo ${var.environment}/${each.key}"
  vpc_id      = data.aws_vpc.default.id

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

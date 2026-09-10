resource "aws_instance" "host" {
  for_each = local.tenants

  ami                    = local.ami_id
  instance_type          = try(each.value.instance_type, var.default_instance_type)
  subnet_id              = local.subnet_id
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
    Name   = local.names[each.key]
    Tenant = each.key
  }

  lifecycle {
    # Removing a tenant from the environment file must not silently terminate a
    # running host. Deleting one is deliberate: remove this block, then apply.
    prevent_destroy = true

    # Both of these would otherwise force the instance to be replaced -- which
    # is a destroy, and neither a new image nor a re-resolved subnet should
    # terminate a running host on its own. New tenants pick up the current
    # values; existing hosts are rolled deliberately (see README).
    ignore_changes = [ami, subnet_id]
  }
}

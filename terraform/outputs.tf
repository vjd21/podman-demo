output "instance_id" {
  value = aws_instance.podman_host.id
}

output "instance_name" {
  value = var.instance_name
}

output "public_ip" {
  value = aws_instance.podman_host.public_ip
}

output "private_ip" {
  value = aws_instance.podman_host.private_ip
}

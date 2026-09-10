# Consumed by the application pipeline to build its deploy matrix. Emitting it
# as a list keeps the pipeline free of any script: the workflow passes this
# straight into a job matrix.
output "targets" {
  description = "One entry per tenant host: name tag, instance id and port."
  value = [
    for id, cfg in local.tenants : {
      tenant      = id
      name        = local.names[id]
      instance_id = aws_instance.host[id].id
      port        = try(cfg.port, 8081)
    }
  ]
}

output "public_ips" {
  value = { for id, _ in local.tenants : id => aws_instance.host[id].public_ip }
}

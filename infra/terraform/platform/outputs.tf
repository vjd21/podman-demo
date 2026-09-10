output "deploy_role_arn" {
  description = "Role assumed by the application pipeline for signing and deploys."
  value       = aws_iam_role.deploy.arn
}

output "infra_provision_role_arn" {
  description = "Role assumed by the custom-image and infrastructure pipelines."
  value       = aws_iam_role.infra_provision.arn
}

output "host_instance_profile" {
  description = "Instance profile name to pass to the app stack's iam_instance_profile."
  value       = aws_iam_instance_profile.host.name
}

output "cosign_kms_key_alias" {
  description = "Alias cosign signs with. Matches COSIGN_KMS_KEY in deploy.yml."
  value       = aws_kms_alias.cosign.name
}

output "ssm_transfer_bucket" {
  description = "Bucket the Ansible aws_ssm connection stages files through."
  value       = aws_s3_bucket.ssm_transfer.id
}

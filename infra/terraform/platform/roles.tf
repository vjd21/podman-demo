############################################
# deploy-role -- assumed by .github/workflows/deploy.yml
############################################

resource "aws_iam_role" "deploy" {
  name                 = "deploy-role"
  description          = "GitHub Actions build/sign/deploy. Least privilege: no AdministratorAccess."
  assume_role_policy   = data.aws_iam_policy_document.github_assume_role.json
  max_session_duration = 3600
}

# deploy-role currently carries the AWS-managed AdministratorAccess policy, which
# makes its scoped inline policy decorative. This resource declares the complete
# set of managed policies as empty, so applying detaches AdministratorAccess and
# nothing can silently re-attach it out of band.
resource "aws_iam_role_policy_attachments_exclusive" "deploy" {
  role_name   = aws_iam_role.deploy.name
  policy_arns = []

  # The one-time bootstrap runs AS deploy-role, using the very AdministratorAccess
  # this resource removes. If the detach happened first, the rest of the apply
  # would lose its permissions half-way through. Forcing it last means the apply
  # closes the hole as its final act.
  depends_on = [
    aws_iam_role_policy.deploy,
    aws_iam_role_policy.infra_provision,
    aws_iam_role_policy.host,
    aws_iam_role_policy_attachment.host_ssm,
    aws_iam_instance_profile.host,
    aws_kms_key.cosign,
    aws_kms_alias.cosign,
    aws_iam_openid_connect_provider.github,
  ]
}

data "aws_iam_policy_document" "deploy" {
  # Sign the image digest with the cosign KMS key, and export its public half for
  # the host. No kms:CreateKey, no kms:ScheduleKeyDeletion.
  statement {
    sid       = "KmsSignForCosign"
    effect    = "Allow"
    actions   = ["kms:Sign", "kms:GetPublicKey", "kms:DescribeKey"]
    resources = [aws_kms_key.cosign.arn]
  }

  # Ansible's amazon.aws.aws_ec2 dynamic inventory.
  statement {
    sid       = "Ec2DynamicInventory"
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }

  # Ansible's amazon.aws.aws_ssm connection plugin. StartSession cannot be scoped
  # to a resource in a useful way, so it is bounded by the instance's own tag.
  statement {
    sid    = "SsmSessionForAnsible"
    effect = "Allow"
    actions = [
      "ssm:StartSession",
      "ssm:TerminateSession",
      "ssm:ResumeSession",
      "ssm:DescribeSessions",
      "ssm:GetConnectionStatus",
      "ssm:DescribeInstanceInformation",
    ]
    resources = ["*"]
  }

  # The bucket aws_ssm uses to move files onto the host.
  statement {
    sid    = "S3FileTransferForSsm"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [
      "arn:aws:s3:::${var.ssm_transfer_bucket}",
      "arn:aws:s3:::${var.ssm_transfer_bucket}/*",
    ]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "podman-demo-pipeline-scoped"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

# The previous inline policy also granted ECR push. Nothing uses it -- images go
# to ghcr.io -- so it is dropped here rather than carried forward.
resource "aws_iam_role_policies_exclusive" "deploy" {
  role_name    = aws_iam_role.deploy.name
  policy_names = [aws_iam_role_policy.deploy.name]
}

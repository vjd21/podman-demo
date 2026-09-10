# The bucket Ansible's amazon.aws.aws_ssm connection plugin stages files
# through. It replaces "sriharis3bucket" -- a bucket this project did not own,
# whose name said nothing about what it was for and which was shared with
# whatever else was using it.
#
# The name is derived from the account id, so nothing needs to record it: the
# deploy pipeline builds the same string from sts:GetCallerIdentity.
locals {
  ssm_transfer_bucket = "podman-demo-ssm-transfer-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "ssm_transfer" {
  bucket = local.ssm_transfer_bucket

  # Staged files only. Nothing here is a source of truth.
  force_destroy = true

  # infra-provision-role can only create this once it has been granted the
  # bucket permissions below, and IAM is eventually consistent. If the very
  # first apply fails here, re-run it -- the policy will have landed.
  depends_on = [aws_iam_role_policy.infra_provision]
}

resource "aws_s3_bucket_public_access_block" "ssm_transfer" {
  bucket                  = aws_s3_bucket.ssm_transfer.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ssm_transfer" {
  bucket = aws_s3_bucket.ssm_transfer.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Deploy artefacts are transient. Nothing should linger here.
resource "aws_s3_bucket_lifecycle_configuration" "ssm_transfer" {
  bucket = aws_s3_bucket.ssm_transfer.id

  rule {
    id     = "expire-staged-transfers"
    status = "Enabled"

    filter {}

    expiration {
      days = 1
    }
  }
}

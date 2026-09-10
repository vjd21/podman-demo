# The cosign signing key. The private half never leaves KMS -- CI signs through
# the role it already assumed, and the public half is exported at deploy time
# rather than committed to the repository.
resource "aws_kms_key" "cosign" {
  description              = "cosign image signing key for podman-demo"
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = "ECC_NIST_P256"
  enable_key_rotation      = false # not supported for asymmetric keys
  deletion_window_in_days  = 30

  policy = data.aws_iam_policy_document.cosign_key.json
}

resource "aws_kms_alias" "cosign" {
  name          = "alias/podman-demo-cosign"
  target_key_id = aws_kms_key.cosign.key_id
}

data "aws_iam_policy_document" "cosign_key" {
  # Without this the key becomes unmanageable if the stack's own access is lost.
  statement {
    sid       = "AccountAdminManagesKey"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_id}:root"]
    }
  }

  # Only the deploy role may sign. Enforced by the key policy itself, so it holds
  # even if an identity policy elsewhere in the account grants kms:Sign.
  statement {
    sid       = "OnlyDeployRoleMaySign"
    effect    = "Allow"
    actions   = ["kms:Sign", "kms:GetPublicKey", "kms:DescribeKey"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.deploy.arn]
    }
  }

  # Verification needs no credentials, but make the public half readable so the
  # key can be inspected without signing rights.
  statement {
    sid       = "AnyoneInAccountMayVerify"
    effect    = "Allow"
    actions   = ["kms:Verify", "kms:GetPublicKey", "kms:DescribeKey"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_id}:root"]
    }
  }
}

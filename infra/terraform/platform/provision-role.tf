############################################
# infra-provision-role -- assumed by the custom-image and infrastructure pipelines
############################################

resource "aws_iam_role" "infra_provision" {
  name                 = "infra-provision-role"
  description          = "GitHub Actions Terraform/Packer. Manages this platform stack and the EC2 host."
  assume_role_policy   = data.aws_iam_policy_document.github_assume_role.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachments_exclusive" "infra_provision" {
  role_name   = aws_iam_role.infra_provision.name
  policy_arns = []
}

data "aws_iam_policy_document" "infra_provision" {
  statement {
    sid    = "Ec2Describe"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "ec2:GetConsoleOutput",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "TerraformEc2Lifecycle"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:ModifyInstanceAttribute",
    ]
    resources = ["*"]
  }

  # Each tenant gets its own security group, so opening a port for one cannot
  # expose another. Managing them needs create/delete plus rule authorisation --
  # RunInstances alone is not enough.
  statement {
    sid    = "TenantSecurityGroups"
    effect = "Allow"
    actions = [
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules",
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
      "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "PackerAmiLifecycle"
    effect = "Allow"
    actions = [
      "ec2:CreateImage",
      "ec2:RegisterImage",
      "ec2:DeregisterImage",
      "ec2:CopyImage",
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot",
      "ec2:CreateKeyPair",
      "ec2:DeleteKeyPair",
      "ec2:ImportKeyPair",
      "ec2:ModifyImageAttribute",
      "ec2:ModifySnapshotAttribute",
    ]
    resources = ["*"]
  }

  # Attach the host profile to instances it launches. Scoped to the one
  # least-privilege role -- it can no longer pass the account's admin role.
  statement {
    sid       = "PassHostInstanceProfile"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.host.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  # Manage this stack from CI. Scoped to exactly the three roles and one instance
  # profile this project owns, so it cannot touch any other principal in the account.
  statement {
    sid    = "ManageOwnIamResources"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRoleTags",
      "iam:GetRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = [
      aws_iam_role.deploy.arn,
      aws_iam_role.infra_provision.arn,
      aws_iam_role.host.arn,
    ]
  }

  statement {
    sid    = "ManageHostInstanceProfile"
    effect = "Allow"
    actions = [
      "iam:GetInstanceProfile",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
    ]
    resources = ["arn:aws:iam::${var.account_id}:instance-profile/${local.host_profile_name}"]
  }

  statement {
    sid    = "ManageGithubOidcProvider"
    effect = "Allow"
    actions = [
      "iam:GetOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:TagOpenIDConnectProvider",
    ]
    resources = [aws_iam_openid_connect_provider.github.arn]
  }

  statement {
    sid    = "ManageCosignKey"
    effect = "Allow"
    actions = [
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:PutKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListResourceTags",
      "kms:TagResource",
      "kms:UntagResource",
    ]
    resources = [aws_kms_key.cosign.arn]
  }

  statement {
    sid       = "ReadKmsAliases"
    effect    = "Allow"
    actions   = ["kms:ListAliases"]
    resources = ["*"]
  }

  # Terraform remote state for both stacks under this prefix.
  statement {
    sid       = "TerraformStateObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/dev/podman-demo/*"]
  }

  statement {
    sid       = "TerraformStateBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = ["arn:aws:s3:::${var.state_bucket}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["dev/podman-demo/*"]
    }
  }

  # Letting CI manage IAM is itself a privilege-escalation path: the role could
  # otherwise grant one of "its" roles administrator rights and assume it. These
  # denies close that path. A Deny always wins over any Allow above.
  statement {
    sid       = "DenyAttachingPrivilegedManagedPolicies"
    effect    = "Deny"
    actions   = ["iam:AttachRolePolicy"]
    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "iam:PolicyARN"
      values = [
        "arn:aws:iam::aws:policy/AdministratorAccess",
        "arn:aws:iam::aws:policy/PowerUserAccess",
        "arn:aws:iam::aws:policy/IAMFullAccess",
      ]
    }
  }

  # It manages the *definitions* of these roles but must never be able to widen
  # who may assume them, nor read credentials for them.
  statement {
    sid       = "DenySelfAssumeAndUserCreation"
    effect    = "Deny"
    actions   = ["iam:CreateUser", "iam:CreateAccessKey", "iam:CreateLoginProfile", "iam:CreatePolicyVersion"]
    resources = ["*"]
  }

}

resource "aws_iam_role_policy" "infra_provision" {
  name   = "podman-demo-infra-provision-scoped"
  role   = aws_iam_role.infra_provision.id
  policy = data.aws_iam_policy_document.infra_provision.json
}

resource "aws_iam_role_policies_exclusive" "infra_provision" {
  role_name    = aws_iam_role.infra_provision.name
  policy_names = [aws_iam_role_policy.infra_provision.name]
}

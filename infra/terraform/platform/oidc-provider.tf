locals {
  owner = split("/", var.github_repo)[0]
  name  = split("/", var.github_repo)[1]

  # The subjects allowed to assume either CI role. Previously this was
  # "repo:vjd21/*", which let every repository in the account -- and every branch
  # in each of them -- assume roles in this AWS account.
  #
  # Two forms, both exact. This organisation issues tokens in GitHub's immutable
  # -id format, so the readable form alone silently fails every assume with
  # "Not authorized to perform sts:AssumeRoleWithWebIdentity" -- the error names
  # no subject, so check CloudTrail rather than guessing. Keeping the readable
  # form too means the roles keep working if that setting is ever turned off.
  oidc_subjects = [
    "repo:${var.github_repo}:ref:${var.deploy_ref}",
    "repo:${local.owner}@${var.github_owner_id}/${local.name}@${var.github_repo_id}:ref:${var.deploy_ref}",
  ]
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

data "aws_iam_policy_document" "github_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # StringEquals, not StringLike: both values are exact, so no wildcard can
    # creep back in. Multiple values are OR-ed.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.oidc_subjects
    }
  }
}

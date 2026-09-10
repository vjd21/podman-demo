# Everything below already exists in the account, created by hand before this stack
# was written. These import blocks let Terraform adopt them on the next apply with
# no console work and no bootstrap run -- `terraform plan` will show the drift
# between what exists and what the .tf files declare, and apply reconciles it.
#
# Once the first apply succeeds these blocks are inert and can be deleted.

import {
  to = aws_iam_openid_connect_provider.github
  id = "arn:aws:iam::148737623247:oidc-provider/token.actions.githubusercontent.com"
}

import {
  to = aws_iam_role.deploy
  id = "deploy-role"
}

import {
  to = aws_iam_role.infra_provision
  id = "infra-provision-role"
}

import {
  to = aws_kms_key.cosign
  id = "3f4bfce5-8d98-4262-8fb4-880e2bc672ca"
}

import {
  to = aws_kms_alias.cosign
  id = "alias/podman-demo-cosign"
}

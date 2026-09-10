locals {
  host_profile_name = "podman-demo-host"
}

# The instance profile the podman host runs under. It replaces the account's
# "admin" profile, which carried AdministratorAccess -- meaning any container
# escape or metadata-service SSRF on that host was full account compromise.
#
# The host makes exactly one kind of AWS call: SSM agent traffic, so Ansible can
# reach it without SSH. Nothing else.
resource "aws_iam_role" "host" {
  name        = local.host_profile_name
  description = "Least-privilege instance profile for the podman-demo host."

  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "host_ssm" {
  role       = aws_iam_role.host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachments_exclusive" "host" {
  role_name   = aws_iam_role.host.name
  policy_arns = [aws_iam_role_policy_attachment.host_ssm.policy_arn]
}

resource "aws_iam_instance_profile" "host" {
  name = local.host_profile_name
  role = aws_iam_role.host.name
}

# The SSM connection plugin stages files through this bucket; the host reads them.
data "aws_iam_policy_document" "host" {
  statement {
    sid       = "SsmFileTransfer"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.ssm_transfer.arn}/*"]
  }
}

resource "aws_iam_role_policy" "host" {
  name   = "podman-demo-host-scoped"
  role   = aws_iam_role.host.id
  policy = data.aws_iam_policy_document.host.json
}

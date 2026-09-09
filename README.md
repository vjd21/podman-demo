# podman-demo

A container deployment pipeline that will not run an image unless it can prove where the
image came from. An nginx image is built and pushed to GHCR, signed twice, then deployed
onto an EC2 host as a Podman Quadlet systemd unit. Both signatures are enforced, at two
different layers, and either one failing stops the deploy.

## Layout

| Path | What lives there |
|---|---|
| `app/` | The application image: `Containerfile` and `index.html`. |
| `infra/packer/` | Packer template that bakes the golden AMI (podman + cosign + policy pre-installed). |
| `infra/terraform/` | Terraform for the EC2 host. S3 remote state, `use_lockfile` for locking. |
| `infra/iam/` | `trust-policy.json` — the GitHub OIDC trust policy the CI roles assume. Reference copy; applied out of band, not by any workflow. |
| `deploy/ansible/` | `deploy.yml` (the deploy playbook) and `aws_ec2.yml` (dynamic inventory over SSM). |
| `deploy/host/` | Files installed onto the host: `policy.json`, `cosign.pub`, `registries.d/ghcr.yaml`, the `podman-demo.container.j2` Quadlet template, and `setup.sh` for AMI bake time. |
| `docs/` | Why keyless signing cannot be enforced by podman's `policy.json`, and how to tell the three stacked failure modes apart. |
| `.github/workflows/` | The three workflows below. |

## Workflows

All three are `workflow_dispatch` only. Run them in this order the first time:

1. **Build Golden AMI (Packer)** — `build-ami.yml`. Bakes an AMI from Ubuntu with podman,
   the AWS CLI, cosign, and `policy.json` already in place. Prints the AMI id.
2. **Provision EC2 (Terraform)** — `provision-ec2.yml`. Takes `instance_name`, an optional
   `ami_id` (the output of step 1), and a `plan` / `apply` / `destroy` action.
3. **Build and Deploy** — `deploy.yml`. Takes `instance_name` — it must match the Name tag
   used in step 2, since that tag is how the Ansible dynamic inventory finds the host.

Steps 1 and 2 use `infra-provision-role`; step 3 uses `deploy-role`. Provisioning
infrastructure and deploying an app are deliberately separate privilege tiers.

## The two signature gates

Every image is signed twice, because neither signature alone can be both strongly bound
and enforceable by podman.

| Signature | Enforced by | What it proves |
|---|---|---|
| Keyless (Fulcio + Rekor) | `cosign verify --certificate-identity` in the Quadlet unit's `ExecStartPre` | This exact workflow on this exact ref signed it; publicly verifiable via the transparency log |
| AWS KMS key | podman `policy.json` (`sigstoreSigned` + `keyPath`) at pull time | Signed by a key we control — admission control before the image enters local storage |

The keyless certificate carries the stronger claim but podman cannot express it, because
its Fulcio matcher only matches an email SAN and GitHub Actions certificates carry a URI
SAN. The full explanation, including the two configuration defects that mask it and how to
distinguish all three, is in
[docs/why-keyless-cannot-be-enforced.md](docs/why-keyless-cannot-be-enforced.md). Read that
before changing anything about signing.

Other invariants worth keeping:

- Deploys always reference an **immutable digest** (`repo@sha256:…`), never a tag. The
  playbook asserts this and refuses to run otherwise. Content addressing is what makes
  "the image I verified" and "the image that runs" the same image.
- `ExecStartPre` must have no `-` prefix, or verification stops being fail-closed.
- Cosign must be **v2.x** everywhere. v3 writes OCI 1.1 referrers that containers/image
  cannot read, so the format written must be the format verified. CI
  (`.github/workflows/deploy.yml`) and the deploy playbook both pin `v2.6.5`.
  **Known inconsistency:** `deploy/host/setup.sh` still pins `v3.1.3` at AMI bake time. The
  playbook replaces it with `v2.6.5` on every deploy, so deploys work — but a freshly baked
  AMI carries a cosign that cannot verify what this pipeline signs until the first deploy
  runs. Align that pin before relying on the AMI standalone.
- A failed pull leaves the previous container running and untouched.

## Rotating the KMS key

`deploy/host/cosign.pub` is the public half of `awskms:///alias/podman-demo-cosign`, kept
in the repo because `policy.json` accepts only a PEM key, not a KMS reference. The deploy
workflow diffs the committed key against the live KMS key and fails if they differ. After
rotating, re-export it:

```bash
cosign public-key --key awskms:///alias/podman-demo-cosign > deploy/host/cosign.pub
```

## Requirements

podman **4.4 or newer** on the host — 4.2 for the `sigstoreSigned` policy type, 4.4 for
Quadlet. The playbook checks the version and fails early if it is too old.

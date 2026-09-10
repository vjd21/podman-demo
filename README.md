# podman-demo

A container deployment pipeline that will not run an image unless it can prove where the
image came from. An nginx image is built and pushed to GHCR, signed twice, then deployed
onto an EC2 host as a Podman Quadlet systemd unit. Both signatures are enforced, at two
different layers, and either one failing stops the deploy.

## Layout

| Path | What lives there |
|---|---|
| `app/` | The application image: `Containerfile` and `index.html`. |
| `infra/packer/` | `podman-host.pkr.hcl` and the `provision-host.sh` it runs, which bakes the custom image (podman + cosign + policy pre-installed). |
| `envs/` | One YAML file per environment (`dev.yaml`), listing that environment's tenants. |
| `infra/terraform/environment/` | The environment stack: one security group and one host per tenant, via `for_each`. S3 remote state, `use_lockfile` for locking. Separate state from the platform stack, so destroying the instance cannot take the CI roles or the signing key with it. |
| `infra/terraform/platform/` | Account-wide: the GitHub OIDC provider, both CI roles and their trust policies, the cosign KMS key, and the least-privilege host instance profile. Adopts the existing hand-made resources via `import` blocks, so no bootstrap run and no console work. |
| `deploy/ansible/` | `site.yml`, the deploy playbook. The SSM inventory is generated per tenant by the application pipeline, not committed. |
| `deploy/host/containers/` | Installed to `/etc/containers/` on the host: `policy.json` and `registries.d/ghcr.yaml`. The directory mirrors its destination. |
| `deploy/host/quadlet/` | The `podman-demo.container.j2` systemd unit template. No key material — the cosign public key is exported from KMS at deploy time. |
| `docs/` | Why keyless signing cannot be enforced by podman's `policy.json`, and a record of every issue hit building this pipeline with the cause and fix for each. |
| `.github/workflows/` | The four workflows below. |

## Pipelines

Three stages, each one's output passed as the next one's input, plus
`pipeline.yml` which runs the chain end to end.

| Stage | Takes | Gives |
|---|---|---|
| **1 · Custom Image** — `1-custom-image.yml` | — | `ami_id` |
| **2 · Infrastructure** — `2-infrastructure.yml` | `environment`, `ami_id` | `targets` |
| **3 · Application** — `3-application.yml` | `environment`, `targets` | the running container |

Each stage is also runnable on its own with `workflow_dispatch`, so a code-only
change is just stage 3 and a tenant added to `envs/dev.yaml` is stage 2 then 3.

Stage 2 applies two stacks in order: the account-wide **platform** stack (OIDC
provider, CI roles, cosign KMS key, host instance profile) and then the
**environment** stack. They keep separate state.

There are no secrets anywhere — not in the repository, not in GitHub. AWS access
is OIDC, the signing key never leaves KMS, and GHCR is public so the host pulls
unauthenticated. If a secret is ever genuinely needed it goes in AWS Secrets
Manager, read at run time by whichever workload needs it through that workload's
own IAM role. Nothing creates one today, so nothing is granted access to one.

The platform stack was originally applied by a one-time `bootstrap.yml`, which
borrowed `deploy-role` while it still held `AdministratorAccess` and used it to
apply the stack that strips that very policy. That has run; the workflow is
deleted. `infra-provision-role` now holds the scoped IAM permissions the
pipelines need, so stage 2 manages the platform stack from here on.

## Environments and tenants

`envs/<name>.yaml` is one environment. Each has its own Terraform state key
(`dev/podman-demo/<name>/infra.tfstate`), so environments never share state.

Tenants sit inside an environment and are separated by instance, security group
and Name tag (`<environment>-<tenant>`) within a single AWS account. Adding one
is a few lines in the environment file.

```yaml
tenants:
  demo:
    instance_type: t3.micro
    port: 8081
```

Rebuilding the custom image does **not** replace running hosts -- `ami` is in
`ignore_changes`, because replacing an instance is a destroy and an image
rebuild should not quietly terminate a live host. New tenants get the newest
image. To roll an existing host onto it, do it deliberately:

```bash
terraform -chdir=infra/terraform/environment apply -replace='aws_instance.host["demo"]'
```

That still needs `prevent_destroy` lifted for that resource first -- which is
the point: it is a decision, not a side effect.

Removing a tenant does **not** destroy it. `prevent_destroy` is set on the
instances and stage 2 fails the run if the plan contains any deletion, so a bad
merge or a revert cannot delete a live host. Tearing one down is deliberate.

**Future:** one AWS account per tenant. That needs AWS Organizations, which this
account is not part of today, so it is deliberately not built.

## Build versioning

Each run of **Build and Deploy** is `v1.0.<run_number>`, taken from the Actions run
counter. The run title shows it (`v1.0.47 → e1087`), the image carries it as a tag and as
`org.opencontainers.image.version`, and the job summary prints version, commit and digest
together.

The version tag is a handle for humans, not a deployment input. GHCR tags are mutable, so
the pipeline signs the digest and the playbook refuses any `new_image_ref` without
`@sha256:`. Both tags are pushed from one build and the workflow fails if they resolve to
different digests — that would mean only one of them is covered by the signature.

To move to real semver later, replace `IMAGE_VERSION` in `deploy.yml` with a value derived
from git tags; nothing downstream depends on the `v1.0.N` shape.

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
  `infra/packer/provision-host.sh` pins the same `v2.6.5` at AMI bake time, so a freshly baked custom image
  can verify what this pipeline signs without waiting for the first deploy to correct it.
- A failed pull leaves the previous container running and untouched.

## Rotating the KMS key

Nothing to do. No key of any kind is committed to this repository.

`policy.json` accepts only a PEM key on disk, not a KMS reference, so the host still needs
the public half of `awskms:///alias/podman-demo-cosign` at `/etc/containers/cosign.pub`.
The deploy workflow exports it fresh from KMS on every run and the playbook installs it,
so the host always holds the public half of the key that actually signed the image. A
rotation is picked up by the next deploy with no manual re-export and no drift to detect.

The playbook refuses to run if `cosign_public_key_path` is not supplied — there is no
committed key to silently fall back to.

## Requirements

podman **4.4 or newer** on the host — 4.2 for the `sigstoreSigned` policy type, 4.4 for
Quadlet. The playbook checks the version and fails early if it is too old.

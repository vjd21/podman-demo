# Why keyless signing cannot be enforced by podman's `policy.json`

Keyless cosign signing works. What does *not* work is making podman verify a keyless
signature at pull time through `/etc/containers/policy.json`. This document records why,
because the failure is non-obvious and the error message actively misleads.

## Summary

Three separate defects stack up, at three different layers. Two are fixable; the first is
not.

| # | Layer | Question it answers | Defect | Fixable? |
|---|-------|--------------------|--------|----------|
| 1 | Identity | *Who signed it?* | podman's Fulcio matcher can only match an **email**, but GitHub Actions certificates contain a **URI** | **No** — unimplemented upstream |
| 2 | Config | *Does podman even look?* | `use-sigstore-attachments` defaults to `false` | Yes — `registries.d` |
| 3 | Storage | *Does it look in the right place?* | cosign v3 writes OCI 1.1 referrers that containers/image cannot read | Yes — pin cosign v2.x |

You must clear 2 and 3 before you can even *reach* 1, which is a hard stop.

**The trap:** defects 2 and 3 produce the *same* error as a genuinely missing signature:

```
Source image rejected: A signature was required, but no signature exists
```

That reads as "your signature is wrong." It actually means "I never found one." Only
defect 1 produces a distinct message. See *Telling them apart* below.

---

# Defect 1 — the identity cannot be expressed (fatal)

## What it is

podman can verify *that* an image was signed via Fulcio, but cannot express *which
GitHub workflow* signed it.

## Why it happens

Keyless signing exchanges the workflow's OIDC token at Fulcio for a short-lived
certificate. For GitHub Actions, the identity lands in the certificate as a **URI SAN**:

```
https://github.com/vjd21/podman-demo/.github/workflows/deploy.yml@refs/heads/main
```

There is no email SAN. A workflow is a machine identity — GitHub's OIDC token carries no
verified email claim, so Fulcio has nothing to write into one. Fulcio only ever certifies
claims the identity provider asserted; it cannot invent an email.

podman's entire identity check, in `containers/image/signature/fulcio_cert.go`, is:

```go
if !slices.Contains(untrustedCertificate.EmailAddresses, f.subjectEmail)
    → "Required email %q not found (got %q)"
```

It reads `EmailAddresses` and nothing else. Against a certificate with zero email SANs,
this can never match.

## The field is mandatory and cannot be blanked

`subjectEmail: ""` is not a wildcard. It is a parse error:

```go
if res.SubjectEmail == "" {
    return nil, InvalidPolicyFormatError("subjectEmail not specified")
}
```

An invalid `policy.json` breaks **every** podman command on the host — including images
from unrelated registries — not just pulls from the affected repository.

## Upstream knows

A `FIXME` sits beside the matching code:

> FIXME: Match more subject types? Cosign does:
> - `.DNSNames` (can't be issued by Fulcio)
> - `.IPAddresses` (can't be issued by Fulcio)
> - `.URIs` (CAN be issued by Fulcio)
> - OtherName values in SAN (CAN be issued by Fulcio)
> - Various values about GitHub workflows (CAN be issued by Fulcio)

The `fulcio` block accepts only `caData`/`caPath`, `oidcIssuer`, and `subjectEmail`. There
is no `subject`, `subjectURI`, or regexp field.

## Why `cosign verify` succeeds on the same signature

`cosign verify` has `--certificate-identity` and `--certificate-identity-regexp`, which
match the URI SAN directly. Same certificate, same signature, same Rekor entry — a
different verifier with more complete feature coverage. Nothing is missing from the
signature; podman simply has no field in which to express the constraint.

## Why no cloud provider fixes it

An email-bearing certificate requires an OIDC issuer that Fulcio trusts with `type: email`.

- **AWS** — not an OIDC *provider* at all. It consumes OIDC (that is how a workflow assumes
  a role) but issues no ID tokens for IAM identities. Its only entry in Fulcio's trusted
  list is `https://oidc.eks.*.amazonaws.com/id/*`, typed `kubernetes`, which produces a URI
  SAN — the same unmatched shape — and requires an EKS cluster.
- **Google** — works: service-account ID tokens carry a verified `email` claim, and
  `https://accounts.google.com` is an `email`-type issuer. This is the only automatable
  path, at the cost of a second cloud provider.
- **Self-hosted Fulcio** — possible (`--ca=kmsca` supports AWS KMS), but you would still
  need an email-bearing machine identity, and you become your own CA, IdP, and verifier.

## Fix

There is none at the identity layer. Sidestep it: sign with a **key** (`keyPath` /
`keyData`, including an AWS KMS key). Verifying against a public key involves no
certificate, no SANs, and no identity matching, so the entire defect disappears.

---

# Defect 2 — podman never looks for the signature

## What it is

A configuration default means podman does not fetch signature attachments at all. It is
not that verification fails — verification never starts.

## Why it happens

`use-sigstore-attachments` defaults to `false`. In
`containers/image/docker/registries_d.go`, `useSigstoreAttachments()` checks the exact
repository scope, then each parent namespace, then `default-docker`, and if none set the
field, ends in:

```go
return false
```

When disabled, the documentation states images are "treated as if no attachments exist."

## How to confirm it is this one

Run the pull with debug logging and look for the lookup line:

```bash
sudo podman --log-level=debug pull ghcr.io/vjd21/podman-demo@sha256:<digest> 2>&1 \
  | grep -i "sigstore attachments"
```

- Line **absent** → attachments are disabled; this defect.
- `Looking for sigstore attachments in …` present → podman is looking; not this defect.

Also simply check the file exists and is readable by the user running podman:

```bash
cat /etc/containers/registries.d/ghcr.yaml
```

## Fix

```yaml
# /etc/containers/registries.d/ghcr.yaml
docker:
    ghcr.io/vjd21/podman-demo:
        use-sigstore-attachments: true
```

Scope it per repository, per registry, or globally under `default-docker`.

## Gotcha

Rootless podman reads `~/.config/containers/registries.d/` **instead of**
`/etc/containers/registries.d/`, not merged with it. The same shadowing applies to
`policy.json`. A frequent false lead when a root deploy works and a manual rootless test
does not.

---

# Defect 3 — cosign v3 writes a format podman cannot read

## What it is

The signature exists in the registry, but stored under a convention podman cannot
discover.

## Why it happens

Cosign does not embed signatures in the image; it stores them as separate registry
objects. Two conventions compete:

| Convention | Stored as | Understood by |
|---|---|---|
| **Legacy** | a tag literally named `sha256-<digest>.sig` | cosign **and** podman |
| **OCI 1.1 referrers** | an artifact with a `subject` field pointing at the image, found via the Referrers API | cosign **only** |

cosign v3 made the referrers form the default. containers/image resolves only the legacy
tag:

```go
strings.Replace(d.String(), ":", "-", 1) + ".sig"
```

and does a plain tag fetch. There is **no Referrers API support** anywhere in it.

## How to confirm it is this one

Ask the registry directly. The legacy tag should exist:

```bash
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:vjd21/podman-demo:pull&service=ghcr.io" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
D=<digest-hex-without-sha256:>

curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer $TOKEN" \
  "https://ghcr.io/v2/vjd21/podman-demo/manifests/sha256-$D.sig"
```

- `200` → legacy signature present; not this defect.
- `404` → no legacy tag. Check whether a referrer exists instead:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://ghcr.io/v2/vjd21/podman-demo/manifests/sha256-$D" | python3 -m json.tool
```

An `artifactType` of `application/vnd.dev.sigstore.bundle.v0.3+json` with a `subject`
field confirms the signature was written as an OCI referrer.

`cosign triangulate <image>@<digest>` prints the legacy location cosign *would* use, which
is the tag podman looks for.

## Fix

Pin cosign to **v2.x** (`v2.6.5` at time of writing), where `--new-bundle-format` defaults
to `false` and the legacy tag is written. That flag **does not exist** in cosign v3.1.3's
`sign` command, so there is no way to opt out on v3. `--registry-referrers-mode` controls
fetching, not the payload format, so it does not help either.

**CI and host must pin the same version**, or the format written will not be the format
verified.

Same root cause as
[coreos/rpm-ostree#5509](https://github.com/coreos/rpm-ostree/issues/5509).

---

# Telling them apart

All three block the pull. Work through them in this order:

1. Is `/etc/containers/registries.d/` configured with `use-sigstore-attachments: true`?
   No → **defect 2**.
2. Does `sha256-<digest>.sig` return 200 from the registry? No → **defect 3**.
3. Both fine and the error changes to `Required email "…" not found (got [])` →
   **defect 1**, and you are done: no configuration will fix it.

If the error is still `A signature was required, but no signature exists` after 1 and 2,
the image genuinely was not signed.

---

# What this project does instead

Each image is signed twice, and both gates must pass:

| Signature | Verified by | Gives you |
|---|---|---|
| Keyless (Fulcio + Rekor) | `cosign verify --certificate-identity` in the Quadlet unit's `ExecStartPre` | Workflow identity binding, public transparency log, external verifiability |
| AWS KMS key | podman `policy.json` (`sigstoreSigned` + `keyPath`) at pull time | System-wide admission control before the image enters local storage |

Fulcio carries the stronger claim — "signed by *this workflow on this ref*" — but only
`cosign verify` can check it. The KMS key carries the weaker claim — "signed by a key I
control" — but podman can enforce it. Using both means neither limitation binds.

podman cannot call KMS: `policy.json` accepts only a PEM public key, so the public half is
exported to `/etc/containers/cosign.pub`. Verification stays offline, but the file must be
re-exported whenever the KMS key is rotated.

# Other gotchas

- `signedIdentity` of type `exactRepository` **requires** a `dockerRepository` field; the
  type alone is a parse error.
- `sigstoreSigned` requires podman ≥ 4.2; Quadlet requires ≥ 4.4.
- `ExecStartPre` must have no `-` prefix, or a failed verification stops being fail-closed.
- Always deploy by immutable digest (`repo@sha256:…`). Content addressing is what
  guarantees the image that was verified is the image that runs.

# Issues faced and how they were fixed

A record of every problem hit while removing committed key material, putting IAM
under Terraform, and restructuring the workflows into three chained pipelines.
Each entry gives the symptom as it actually appeared, the real cause, and the
fix, so the same error text can be found by searching this file.

File and workflow names in this document are the ones in use at the time each
issue occurred. Several have since been renamed -- `3-app.yml` is now
`3-application.yml`, and `deploy/ansible/deploy.yml` is now `site.yml`. The
error text is left exactly as it appeared so it can still be searched for.

Two themes run through almost all of it:

- **Tightening a scope without re-deriving what the scope needs.** Most pipeline
  failures were a permission or a path that was correct for the old design and
  silently wrong for the new one.
- **Errors that name the wrong thing.** AWS and Terraform reported several of
  these in ways that pointed away from the cause. Where that happened, the entry
  says where the real answer was found.

---

## Security findings

These were found by inspecting the live account, not by anything failing. None
of them produced an error message; they were all working exactly as configured.

### 1. `deploy-role` held `AdministratorAccess`

**Found:** `aws iam list-attached-role-policies --role-name deploy-role`

The role had a carefully scoped inline policy *and* the AWS-managed
`AdministratorAccess` policy attached. The inline policy was therefore
decorative — the managed policy granted everything regardless.

**Fix:** the platform stack declares the complete set of managed policies as
empty via `aws_iam_role_policy_attachments_exclusive`, so applying detaches
`AdministratorAccess` and nothing can silently reattach it out of band.

### 2. OIDC trust allowed every repository in the account

The trust policy condition was:

```json
"StringLike": { "sub": ["repo:vjd21/*", "repo:vjd21@*/*"] }
```

Combined with finding 1, **any repository owned by `vjd21`, on any branch, could
mint AWS account administrator credentials.** A throwaway repo with a workflow
file was full account compromise.

**Fix:** `StringEquals` against exact subjects for this repository's `main`
branch only. See issue 7 below for the part of this that went wrong.

### 3. The host ran with an administrator instance profile

The EC2 instance profile was `admin`, whose role also held
`AdministratorAccess`. Any container escape, or an SSRF reaching the instance
metadata service, was full account compromise.

**Fix:** a new `podman-demo-host` profile carrying only
`AmazonSSMManagedInstanceCore`, plus `http_tokens = "required"` on the instance
to force IMDSv2 and close the SSRF-to-credentials path.

### 4. A public key was committed to the repository

`deploy/host/cosign.pub` was tracked. A public key is not confidential, so this
was not an exposure — but it drifted from its source of truth, which is why a
whole pipeline step existed to diff it against KMS and fail on mismatch.

**Fix:** deleted. The pipeline runs `cosign public-key --key awskms://...` on
every deploy and passes the path to the playbook. Drift became impossible, and
the diff-check step was removed with it. The playbook now fails if no key is
supplied rather than falling back to a committed one.

### 5. A GitHub personal access token was pasted into a terminal prompt

During a `git push`, a `ghp_…` token was typed at the username prompt, putting
it in terminal scrollback in plain text.

**Fix:** the token was revoked and reissued. The underlying cause was that no
git credential helper was configured, so every push prompted for a credential
by hand. Switching the remote to SSH removes the prompt entirely:

```bash
git remote set-url origin git@github.com:vjd21/podman-demo.git
```

The lesson is the same one the rest of this work applies to AWS: a credential
typed by a human on every operation will eventually end up somewhere it should
not be.

---

## Pipeline failures

In run order. Each one was a separate red run.

### 6. Bootstrap verification failed after a successful apply

```
aws: [ERROR]: An error occurred (AccessDenied) when calling the
ListAttachedRolePolicies operation: ... not authorized to perform
iam:ListAttachedRolePolicies on resource: role deploy-role
```

The apply itself succeeded — `5 imported, 11 added, 3 changed, 0 destroyed`. The
failure was in a verification step that ran **as `deploy-role`**, checking
whether `deploy-role` still had administrator rights, one step after the apply
removed them. The `AccessDenied` was proof the fix had worked.

**Fix:** none needed to the logic. The bootstrap workflow had done its one job
and was deleted, along with the now-inert `import` blocks.

### 7. Every role assumption failed with no indication why

```
Error: Could not assume role with OIDC:
Not authorized to perform sts:AssumeRoleWithWebIdentity
```

The trust policy said `repo:vjd21/podman-demo:ref:refs/heads/main`, the workflow
ran on `main`, and it still failed — eleven retries, then a hard stop.

The error names no subject, so it cannot be diagnosed from the workflow log.
CloudTrail can:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity
```

That showed the subject actually presented:

```
repo:vjd21@112800271/podman-demo@1356067443:ref:refs/heads/main
```

This organisation issues OIDC tokens using GitHub's **immutable-id subject
format**, `owner@ownerID/repo@repoID`. The human-readable form never matches.

This was a regression: the original wildcard policy had a second pattern,
`repo:vjd21@*/*`, which existed precisely for this format. It was read as a
stray and dropped when the trust was tightened to exact matching.

**Fix:** both subjects, both exact, OR-ed by `StringEquals`:

```
repo:vjd21/podman-demo:ref:refs/heads/main
repo:vjd21@112800271/podman-demo@1356067443:ref:refs/heads/main
```

Keeping the readable form means the roles keep working if that organisation
setting is ever turned off. The numeric ids live in `variables.tf` with a note
that they came from CloudTrail and must not be guessed.

Because both roles were affected, no workflow could assume anything, and
`deploy-role` no longer had administrator rights — so this one fix had to be
applied from a workstation. It was the only step in the whole sequence that
could not run in CI.

### 8. Terraform init refused to read state

```
Error refreshing state: Unable to access object
"podman-demo/dev/infra.tfstate" in S3 bucket "aws-terraform-statefiles-bucket":
api error Forbidden: Forbidden
```

`infra-provision-role` grants S3 access on `dev/podman-demo/*`. The new
per-environment backend key was `podman-demo/dev/infra.tfstate` — the same two
segments in the opposite order, so it fell outside the grant.

**Fix:** key changed to `dev/podman-demo/<environment>/infra.tfstate`, and a
comment added to `backend.tf` recording that the prefix is fixed by the IAM
grant, so the next person does not reverse it again.

### 9. Security group creation denied

```
UnauthorizedOperation: You are not authorized to perform this operation.
User: ...assumed-role/infra-provision-role/GitHubActions is not authorized to
perform: ec2:CreateSecurityGroup
```

The role had a full EC2 instance and AMI lifecycle but **no security group write
actions at all**. Per-tenant security groups were new in this design; the policy
had been written against the older config, which reused an existing group.

**Fix:** a `TenantSecurityGroups` statement granting create, delete, and ingress
and egress rule authorisation and revocation.

No local apply was needed: stage 2's `platform` job runs before its `terraform`
job and holds `iam:PutRolePolicy` on its own role, so the pipeline widened its
own policy and the next job picked it up in the same run.

### 10. Instance creation failed with an error naming nothing

```
Error: collecting instance settings: empty result
  with aws_instance.host["demo"]
```

The AWS provider looks up the AMI to determine the root device before calling
`RunInstances`. The lookup returned nothing, because the AMI id hardcoded as the
Terraform default — `ami-04afd14ab83ca1834` — **no longer existed in the
account**. It had been deregistered at some point before this work started, and
was carried forward without being checked.

Confirmed with:

```bash
aws ec2 describe-images --image-ids ami-04afd14ab83ca1834   # returns []
aws ec2 describe-images --owners self                       # shows what exists
```

**Fix:** `ami_id` now defaults to empty and an `aws_ami` data source selects the
most recent `podman-demo-host-*` image the account owns. A supplied id still
wins. A pinned default rots silently; a data source fails naming its filter.

This also removed a manual step — copying the AMI id from the image pipeline
into the infrastructure pipeline by hand.

### 11. The deploy stage was skipped and the run still reported success

Nothing failed. The run was green, and no container was deployed.

```
custom-image     skipped     (rebuild_custom_image = false)
       ↓
infrastructure   ran         (only because it had always())
       ↓
application      skipped     (implicit if: success())
```

GitHub's skip propagation is **transitive**. A job with the default
`if: success()` is skipped when any *ancestor* was skipped, not only a direct
dependency. `infrastructure` escaped it by declaring `always()`; `application`
had no condition and inherited the skip.

The dangerous part is that a skipped job is not a failure, so the pipeline
reported success while silently doing nothing.

**Fix:** an explicit condition on `application`:

```yaml
if: always() && !cancelled() && needs.infrastructure.result == 'success'
```

### 12. The image pulled, then refused to start

```
none of the expected identities matched what was in the certificate,
got subjects [https://github.com/vjd21/podman-demo/.github/workflows/3-app.yml@refs/heads/main]
podman-demo.service: Failed with result 'exit-code'
```

Worth reading carefully, because two gates behaved correctly here: podman
verified the KMS signature and admitted the image, and the keyless
`ExecStartPre` check then refused to start it. Fail-closed worked.

The identity was wrong because `deploy.yml` had been renamed to `3-app.yml`, but
the certificate identity was hardcoded in a Jinja template under `deploy/host/`
— a different directory, with nothing connecting the two.

**Fix:** the identity is now supplied by the pipeline that signs, defined next to
the file it names:

```yaml
COSIGN_IDENTITY: https://github.com/${{ github.repository }}/.github/workflows/3-app.yml@refs/heads/main
```

passed through as `-e cosign_identity=...`, with the playbook asserting it is
set rather than rendering an empty identity.

### 13. An image rebuild deadlocked against the never-destroy rule

```
Plan: 1 to add, 0 to change, 1 to destroy.
Error: Instance cannot be destroyed
Resource aws_instance.host["demo"] has lifecycle.prevent_destroy set
```

Changing `ami` forces EC2 replacement — Terraform cannot swap an AMI in place —
and `prevent_destroy` correctly refused. Both behaviours were right; together
they meant **every custom image rebuild deadlocked the pipeline**.

**Fix, two parts.**

`ignore_changes = [ami]` on the instance. Replacing an instance is a destroy, and
an image rebuild must not quietly terminate a live host. New tenants get the
newest image; existing hosts are rolled deliberately with `-replace=`, which
still requires lifting `prevent_destroy` first. What actually runs on a host is
updated by the application pipeline in any case.

The plan guard was also wrong, and would have blocked this even without
`prevent_destroy`. It tested `actions | index("delete")`, which matches a
replace as well, since a replace is `["delete","create"]` on one address:

| Plan actions | Meaning | Behaviour |
|---|---|---|
| `["delete"]` | tenant removed from the environment file | fail the run |
| `["delete","create"]` | resource replaced | warn, allow |

### 14. The SSM transfer bucket could not be created

```
AccessDenied: ... is not authorized to perform: s3:CreateBucket
```

Replacing the externally-owned `sriharis3bucket` with one this project owns
meant the platform stack now created a bucket — but `infra-provision-role` had
**no S3 bucket permissions at all**, only object permissions on the state
prefix. The same class of mistake as issue 9: the policy fitted the previous
design.

**Fix:** a `ManageSsmTransferBucket` statement scoped to that one bucket ARN.

### 15. …and then could not be read back

```
AccessDenied: ... is not authorized to perform: s3:GetBucketCORS
```

The grant added in 14 was an enumerated list of fifteen actions. After creating
a bucket the AWS provider reads back every sub-resource it knows about — ACL,
policy, tagging, versioning, encryption, lifecycle, logging, website, CORS,
replication, object lock, ownership controls — and the list was missing CORS.
Adding actions one failure at a time is unwinnable, and a provider upgrade that
reads one more sub-resource breaks it again.

**Fix:** `s3:Get*` and `s3:Put*`, scoped to that one bucket ARN written in full.

The principle: an IAM policy has two dials, and they are not equally knowable.
The **resource** is yours and stable; the **action list** is a guess about a
tool's internals. Tighten the resource. Only enumerate actions where they differ
in danger — `kms:Sign` versus `kms:ScheduleKeyDeletion` genuinely do, reading a
bucket's CORS versus its tagging does not. A bucket-level ARN grants nothing on
the objects inside it.

### 16. A deadlock the pipeline could not escape

The fix in 15 never applied. Every run failed identically:

```
terraform refresh  → reads the bucket → GetBucketCORS denied
                   → apply aborts
                   → the policy granting Get* is never written
                   → the next run does exactly the same
```

Terraform refreshes state before planning, so it needed a permission that only
the aborted apply could grant. Re-running could not have helped, however many
times.

Confirmed by reading the live policy after the failure: still the old
enumerated list. **A failure that repeats identically means nothing changed** —
which rules out anything self-resolving, propagation included.

**Fix:** the platform job reconciles the CI role's own policy first, before
anything that depends on it:

```bash
terraform apply -auto-approve -target=aws_iam_role_policy.infra_provision
```

`-target` limits the refresh to that resource and its dependencies. The policy
uses a literal bucket ARN rather than a reference to the bucket resource, so
this pass touches nothing the role cannot already read.

This is not a workaround. A stack that manages the permissions of the role
applying it is inherently ordered, and the ordering was missing.

### 17. The plan ran before the grant took effect

With the deadlock broken, the same run still failed on `GetBucketCORS` — the
plan started seconds after the policy was written, and IAM is eventually
consistent. Distinguishable from 16 only by checking the live policy: this time
the grant *was* there.

**Fix:** a 20-second wait after the self-policy apply, on runs that change it.

---

## What to check first, next time

- **`AccessDenied` on `AssumeRoleWithWebIdentity`** names no subject. Read
  CloudTrail; do not reason about what the subject ought to be.
- **A green pipeline is not a successful one.** Check whether jobs were skipped;
  skipped is not failed, and GitHub propagates skips transitively.
- **After changing what Terraform creates, re-derive the IAM policy.** Three
  separate failures here were permissions that fitted the previous design.
- **A failure that repeats identically means nothing changed.** Check the live
  state after a failure before re-running. If the resource still looks the way
  it did, the run never got far enough to change it, and no amount of retrying
  will help — that distinguishes a deadlock from eventual consistency.
- **A hardcoded id is a future outage.** The AMI, the state key prefix, and the
  certificate identity all broke because a literal in one file had to agree with
  something in another. Derive it, or put it next to what it refers to.

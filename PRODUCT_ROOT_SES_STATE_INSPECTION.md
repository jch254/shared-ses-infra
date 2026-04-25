# Product Root SES State Inspection

Read-only inspection of Namaste and Lush product Terraform roots to confirm SES receipt rule / rule-set ownership before any cleanup pass. No config, state, or live resources were modified.

## Executive summary

Three product Terraform roots were initialized against their intended remote backends and inspected:

- `namaste/infrastructure/terraform` (AWS product root)
- `namaste/infrastructure/terraform/ses-router` (legacy router root)
- `lush-aural-treats/infrastructure` (AWS product root)

Live SES is healthy: `shared-inbound-mail-rules` remains the active rule set in `ap-southeast-2`, and both `gtd-inbound` and `music-submission` are present, enabled, and unchanged with the expected S3-then-Lambda action order and `Event` invocation.

State ownership picture is more entangled than the cleanup plan assumed:

- **Namaste AWS root** owns the *inactive* `gtd-rules` rule set and the inactive `gtd-inbound` rule scoped to `gtd-rules`. No planned SES drift. Safe to scope a future `removed { destroy = false }` cleanup.
- **Lush AWS root** owns the *inactive* `lush-aural-treats-rules` rule set and the inactive `music-submission` rule scoped to `lush-aural-treats-rules`. No planned SES drift. Safe to scope a future `removed { destroy = false }` cleanup.
- **Namaste legacy `ses-router` root** is *not* dormant — its remote state currently owns the **live shared** `shared-inbound-mail-rules` rule set, the **live shared** `gtd-inbound` rule, the **live shared** `music-submission` rule, *and* the `aws_ses_active_receipt_rule_set` resource pointing at `shared-inbound-mail-rules`. Its plan returns "No changes." This is a hard split-ownership conflict with `shared-ses-infra` and is the most important finding in this pass.

No live SES change is being planned by any root; the danger is latent (split state binding), not active drift.

## Namaste product root state findings

Backend (init confirmed):

- bucket: `jch254-terraform-remote-state`
- key: `gtd`
- region: `ap-southeast-4`

State contains:

- `aws_ses_receipt_rule_set` — yes — `aws_ses_receipt_rule_set.main`, id `gtd-rules` (inactive product-local rule set)
- `aws_ses_receipt_rule` — yes — `aws_ses_receipt_rule.inbound`, id `gtd-inbound`, `rule_set_name = "gtd-rules"`
- `aws_ses_active_receipt_rule_set` — no (consistent with the existing `removed { destroy = false }` block in `email.tf`)

Plan (`-refresh=false -input=false -var-file=environments/prod/terraform.tfvars`, with placeholder `TF_VAR_cookie_secret`, `TF_VAR_resend_api_key`, `TF_VAR_email_inbound_secret` to satisfy required variables):

- Plan summary line emitted: `Plan: 1 to add, 4 to change, 1 to destroy.` then errored on missing local Lambda build artifacts (`./lambda/dist/ses-email-forwarder.mjs`, `./lambda/build-notification-formatter/dist/index.js`). The error is a build-artifact issue, not state drift.
- Resources Terraform reported wanting to change, in order:
  - `aws_codebuild_project.main` — in-place update, `IMAGE_TAG` env var `2163c4db -> latest` (image tag drift — unrelated to SES)
  - `aws_ecs_service.main` — in-place update, task definition pointer becomes `(known after apply)` (cascade from task definition replacement)
  - `aws_ecs_task_definition.main` — destroy and replace, image tag pinned vs `latest`, plus a few zero-default attributes (`mountPoints`, `systemControls`, `volumesFrom`) being normalized
  - `aws_ssm_parameter.cookie_secret` — in-place value change (expected: placeholder var, not real secret)
  - `aws_ssm_parameter.resend_api_key` — in-place value change (expected: placeholder var, not real secret)
- No SES receipt rule, rule set, or active rule set resource appeared anywhere in the plan diff.

Planned SES creates / changes / destroys: **none**.

Unrelated planned drift:

- ECS task definition replacement and CodeBuild `IMAGE_TAG` flip from a pinned commit to `latest` — appears to be ordinary deploy-time drift owned by the deploy pipeline, not by an interactive `terraform apply`.
- The two SSM parameter value changes are caused by the placeholder secrets used to satisfy required variables; they are inspection-only artifacts and would not appear with the real values.
- No relevance to SES routing.

## Namaste legacy `ses-router` state findings

Backend (init confirmed):

- bucket: `jch254-terraform-remote-state`
- key: `ses-router/ap-southeast-2`
- region: `ap-southeast-4`

State contains:

- `aws_ses_receipt_rule_set` — yes — `aws_ses_receipt_rule_set.regional`, id **`shared-inbound-mail-rules`**
- `aws_ses_receipt_rule` — yes — both:
  - `aws_ses_receipt_rule.namaste`, id `gtd-inbound` (within `shared-inbound-mail-rules`)
  - `aws_ses_receipt_rule.lush`, id `music-submission` (within `shared-inbound-mail-rules`)
- `aws_ses_active_receipt_rule_set` — yes — `aws_ses_active_receipt_rule_set.regional`, id **`shared-inbound-mail-rules`**

Plan (`-input=false -no-color -var-file=environments/prod/terraform.tfvars`, full refresh allowed):

```
No changes. Your infrastructure matches the configuration.
```

Planned SES creates / changes / destroys: **none right now**.

Unrelated planned drift: none.

Why this is the critical finding:

- This root's state has been migrated/aligned to point at exactly the same live shared rule set, the same two active rules, and the active-rule-set selector that `shared-ses-infra` was intended to be the single owner of.
- Both `shared-ses-infra/infrastructure/aws` and `namaste/infrastructure/terraform/ses-router` therefore co-own `shared-inbound-mail-rules`, `gtd-inbound`, and `music-submission` in remote state.
- `aws_ses_active_receipt_rule_set` is owned **only** by the legacy `ses-router` root — `shared-ses-infra` does not manage it.
- The plan being clean means an accidental `terraform apply` here would currently be a no-op against AWS, but any future config drift in either repo (e.g. shared-ses-infra changes a recipient, S3 bucket, Lambda ARN, or scan setting) will cause one root to attempt to revert the other root's changes.
- The cleanup plan in `SES_PRODUCT_RULE_CLEANUP_PLAN.md` describes this root as "legacy/superseded" and warns "must not be applied"; that warning needs to be hardened with a state-retirement plan before any further SES work touches either repo.

## Lush product root state findings

Backend (read from `versions.tf`, init confirmed — the root hard-codes its backend so `-reconfigure` was used with no overrides):

- bucket: `jch254-terraform-remote-state`
- key: `lush-aural-treats-infrastructure`
- region: `ap-southeast-4`

State contains:

- `aws_ses_receipt_rule_set` — yes — `aws_ses_receipt_rule_set.main`, id `lush-aural-treats-rules` (inactive product-local rule set)
- `aws_ses_receipt_rule` — yes — `aws_ses_receipt_rule.music_submission`, id `music-submission`, `rule_set_name = "lush-aural-treats-rules"`
- `aws_ses_active_receipt_rule_set` — no (consistent with `manage_ses_active_rule_set = false` and the `count = 0` guard in `email.tf`)

Plan (`-refresh=false -input=false -var-file=environments/prod/terraform.tfvars`):

- Plan summary line emitted: `Plan: 1 to add, 2 to change, 1 to destroy.` then errored on missing local Lambda build artifact (`./lambda/build-notification-formatter/dist/index.js`). Build-artifact issue, not state drift.
- Resources Terraform reported wanting to change, in order:
  - `aws_codebuild_project.main` — in-place update, `IMAGE_TAG` env var `40664fe3 -> latest`
  - `aws_ecs_service.main` — in-place update, task definition pointer `(known after apply)`
  - `aws_ecs_task_definition.main` — destroy and replace, image tag pinned vs `latest`, plus the same `mountPoints` / `systemControls` / `volumesFrom` zero-default normalization
- No SES receipt rule, rule set, or active rule set resource appeared in the plan diff.

Planned SES creates / changes / destroys: **none**.

Unrelated planned drift:

- ECS task definition replacement and CodeBuild `IMAGE_TAG` flip from a pinned commit to `latest` — same ordinary deploy-pipeline drift pattern as Namaste.
- No relevance to SES routing.

## Live SES verification

Re-run after state inspections:

```bash
aws ses describe-active-receipt-rule-set --region ap-southeast-2
```

- Active rule set: `shared-inbound-mail-rules` (created `2026-04-25T00:47:58Z`)
- Rule `gtd-inbound`:
  - enabled: true, scan enabled: true, TLS policy: `Optional`
  - recipient: `parse.namasteapp.tech`
  - action 1: S3 bucket `gtd-ses-emails`
  - action 2: Lambda `arn:aws:lambda:ap-southeast-2:352311918919:function:gtd-ses-forwarder`, invocation `Event`
- Rule `music-submission`:
  - enabled: true, scan enabled: true, TLS policy: `Optional`
  - recipient: `parse.lushauraltreats.com`
  - action 1: S3 bucket `lush-aural-treats-ses-emails`
  - action 2: Lambda `arn:aws:lambda:ap-southeast-2:352311918919:function:lush-aural-treats-ses-forwarder`, invocation `Event`

Active rule set unchanged. Both routes present and unchanged. S3-first / Lambda-second order preserved. Lambda invocation type still `Event`.

## Cleanup readiness assessment

Per-root readiness for the next `removed { destroy = false }` cleanup pass described in `SES_PRODUCT_RULE_CLEANUP_PLAN.md`:

- **Namaste AWS product root — ready (scoped to inactive duplicates).** State unambiguously owns only the inactive `gtd-rules` rule set and the inactive `gtd-inbound` rule inside `gtd-rules`. Adding `removed { destroy = false }` blocks for `aws_ses_receipt_rule.inbound` and `aws_ses_receipt_rule_set.main` is safe to plan because nothing this root owns can collide with the active `shared-inbound-mail-rules` rule set: the rule's `rule_set_name` is `gtd-rules`, not the shared one.
- **Lush AWS product root — ready (scoped to inactive duplicates).** Same shape: state owns only the inactive `lush-aural-treats-rules` rule set and the inactive `music-submission` rule inside `lush-aural-treats-rules`. `aws_ses_active_receipt_rule_set` is correctly absent. Adding `removed { destroy = false }` blocks for `aws_ses_receipt_rule.music_submission` and `aws_ses_receipt_rule_set.main` is safe to plan.
- **Namaste legacy `ses-router` root — NOT ready.** This root currently has remote-state ownership of the live shared rule set, both live shared rules, *and* the active-rule-set selector. It must not be applied as-is, and product-root cleanup work in the Namaste/Lush AWS roots should not be sequenced ahead of resolving this root. A `removed { destroy = false }` cleanup applied here would be the correct shape for retiring its state, but it deserves its own reviewed pass before or concurrently with the product-root cleanup, not as an afterthought.

The cleanup plan's Option C → Option B sequencing remains correct for the two AWS product roots. It needs an explicit pre-step covering the `ses-router` root.

## Recommended next step

Before any product-root cleanup apply, add a state-retirement pass for `namaste/infrastructure/terraform/ses-router`:

1. Decide ownership: confirm `shared-ses-infra` is the only intended owner of `shared-inbound-mail-rules`, `gtd-inbound`, `music-submission`, and the active-rule-set selector for `ap-southeast-2`.
2. If yes, prepare a reviewed change to the `ses-router` root that adds `removed { destroy = false }` blocks for:
   - `aws_ses_receipt_rule.namaste`
   - `aws_ses_receipt_rule.lush`
   - `aws_ses_receipt_rule_set.regional`
   - `aws_ses_active_receipt_rule_set.regional`
3. Run plan only and verify Terraform reports forgetting the four state bindings without destroying any live SES resources and without changing the active rule set.
4. Separately (and only after a reviewed plan), decide whether `shared-ses-infra` should also adopt `aws_ses_active_receipt_rule_set` so the active selector is owned somewhere after retirement, or whether to leave it manually managed.
5. Only after the `ses-router` retirement is reviewed, apply or queue the analogous Namaste-AWS-root and Lush-AWS-root removed-block work for the inactive `gtd-rules` / `lush-aural-treats-rules` duplicates.

Do not run `terraform apply` in any of these roots based on this inspection alone.

## Stop conditions

Stop and escalate before any future apply if:

- any plan in any root wants to destroy or replace `shared-inbound-mail-rules`
- any plan wants to destroy or replace `gtd-inbound` or `music-submission` in `shared-inbound-mail-rules`
- any plan wants to deactivate the active SES receipt rule set or change it away from `shared-inbound-mail-rules`
- the `ses-router` root's plan transitions from "No changes" to a non-empty diff before its state is retired
- a Namaste or Lush AWS-root plan starts referencing `shared-inbound-mail-rules` (would indicate misconfigured `removed` blocks)
- `aws ses describe-active-receipt-rule-set --region ap-southeast-2` ever returns anything other than the verified shape above
- product-root plan diff broadens beyond ECS / CodeBuild / SSM image-tag-and-secret churn into buckets, bucket policies, Lambda forwarders, Lambda permissions, IAM, identities, DKIM, or DNS
- state ownership changes in any way — import, `state mv`, `state rm`, or backend reconfiguration outside the values listed in this report

Stop after any future apply if:

- `shared-ses-infra/infrastructure/aws` no longer plans clean
- live SES describe output diverges from the verified shape (rule names, recipients, action order, invocation type, scan enabled, TLS policy)
- either app stops receiving inbound mail through its app-local forwarder/parser path

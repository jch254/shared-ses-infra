# SES Product Rule Apply Strategy

Date: 2026-04-25

## Executive summary

Do not run a full-root product apply for this SES cleanup right now.

The current remote Terraform state for both product roots already no longer tracks the retired product-local SES receipt rule and rule-set addresses. Refreshed and `-refresh=false` targeted plans against the old addresses return `No changes`, so there is no remaining product-local SES state-forget action to apply in this workspace state.

The shared SES root is clean, and live SES still points at the shared active rule set:

- Active rule set: `shared-inbound-mail-rules`
- Namaste route: `gtd-inbound` for `parse.namasteapp.tech`
- Lush route: `music-submission` for `parse.lushauraltreats.com`

Recommended strategy: treat the product-local SES cleanup as already absorbed in state for the current backends. Do not apply anything for SES unless a future pre-apply check shows the retired addresses have reappeared in state or a different workspace/backend still tracks them. If that happens, prefer a targeted declarative removed-block apply only when the targeted plan shows only the expected state-forget actions and no live resource changes. If the targeted plan is ambiguous, wait until unrelated product-root drift is cleared and use the standard full-root workflow.

## Namaste current diff and plan findings

Root: `namaste/infrastructure/terraform`

Git findings:

- `git -C namaste status --short` returned clean.
- `git -C namaste diff --name-status origin/main...HEAD` returned no files.
- Current `HEAD`: `7bfa636 chore(infra): forget inactive SES product rules`.
- `email.tf` contains `removed` blocks with `destroy = false` for:
  - `aws_ses_receipt_rule_set.main`
  - `aws_ses_receipt_rule.inbound`
  - `aws_ses_active_receipt_rule_set.main`

State findings:

- `terraform state list` does not include:
  - `aws_ses_receipt_rule.inbound`
  - `aws_ses_receipt_rule_set.main`
  - `aws_ses_active_receipt_rule_set.main`
- The Namaste product-local SES rule/rule-set bindings are therefore already absent from state.

Plan findings:

- Plain `terraform plan -input=false -no-color` failed because required variables are not supplied locally.
- `terraform plan -input=false -no-color -var-file=environments/prod/terraform.tfvars` still failed because the local environment does not provide the sensitive required variables:
  - `cookie_secret`
  - `resend_api_key`
  - `email_inbound_secret`
- I did not run a full-root Namaste plan with dummy secret values because that would manufacture SSM parameter drift and would not be a reliable apply-safety signal.
- Targeted plan with the retired addresses and `-refresh=false` returned `No changes`.
- Targeted plan with the retired addresses and normal refresh returned `No changes`.

Targeted commands evaluated:

```bash
cd namaste/infrastructure/terraform

terraform plan -input=false -no-color -refresh=false \
  -var-file=environments/prod/terraform.tfvars \
  -target=aws_ses_receipt_rule.inbound \
  -target=aws_ses_receipt_rule_set.main \
  -target=aws_ses_active_receipt_rule_set.main \
  -var=cookie_secret=__PLAN_ONLY_PLACEHOLDER__ \
  -var=resend_api_key=__PLAN_ONLY_PLACEHOLDER__ \
  -var=email_inbound_secret=__PLAN_ONLY_PLACEHOLDER__

terraform plan -input=false -no-color \
  -var-file=environments/prod/terraform.tfvars \
  -target=aws_ses_receipt_rule.inbound \
  -target=aws_ses_receipt_rule_set.main \
  -target=aws_ses_active_receipt_rule_set.main \
  -var=cookie_secret=__PLAN_ONLY_PLACEHOLDER__ \
  -var=resend_api_key=__PLAN_ONLY_PLACEHOLDER__ \
  -var=email_inbound_secret=__PLAN_ONLY_PLACEHOLDER__
```

The placeholder values were used only to satisfy required variable validation for a targeted no-op plan. Do not use placeholder secrets for a full-root plan or apply.

## Lush current diff and plan findings

Root: `lush-aural-treats/infrastructure`

Git findings:

- `git -C lush-aural-treats status --short` returned clean.
- `git -C lush-aural-treats diff --name-status origin/main...HEAD` returned no files.
- Current `HEAD`: `5aff0ac chore(infra): forget inactive SES product rules`.
- `email.tf` contains `removed` blocks with `destroy = false` for:
  - `aws_ses_receipt_rule_set.main`
  - `aws_ses_receipt_rule.music_submission`
- `aws_ses_active_receipt_rule_set.main` remains declared with `count = var.manage_ses_active_rule_set ? 1 : 0`; the documented safe default is still `false`.

State findings:

- `terraform state list` does not include:
  - `aws_ses_receipt_rule.music_submission`
  - `aws_ses_receipt_rule_set.main`
- The Lush product-local SES rule/rule-set bindings are therefore already absent from state.

Plan findings:

- Full-root plan with `-var-file=environments/prod/terraform.tfvars` is not safe to apply for this cleanup. Before failing on a missing local Lambda build artifact, it planned unrelated product drift:
  - `aws_codebuild_project.main` in-place update: `IMAGE_TAG` `5aff0ac7` -> `latest`
  - `aws_ecs_task_definition.main` replacement: container image `5aff0ac7` -> `latest`
  - `aws_ecs_service.main` in-place update to the new task definition
- The full plan then failed because `./lambda/build-notification-formatter/dist/index.js` is missing locally.
- Targeted plan with the retired addresses and `-refresh=false` returned `No changes`.
- Targeted plan with the retired addresses and normal refresh returned `No changes`.

Targeted commands evaluated:

```bash
cd lush-aural-treats/infrastructure

terraform plan -input=false -no-color -refresh=false \
  -var-file=environments/prod/terraform.tfvars \
  -target=aws_ses_receipt_rule.music_submission \
  -target=aws_ses_receipt_rule_set.main

terraform plan -input=false -no-color \
  -var-file=environments/prod/terraform.tfvars \
  -target=aws_ses_receipt_rule.music_submission \
  -target=aws_ses_receipt_rule_set.main
```

## Targeted apply feasibility

Terraform `v1.14.8` is installed locally.

Terraform's official removed-block workflow is to replace the resource block with a `removed` block, set `lifecycle.destroy = false`, run a plan, and then apply the configuration so Terraform removes the binding from state without destroying the real object. Terraform also supports `-target` for exceptional cases by targeting resource or module addresses.

For these two product roots, Terraform accepts the old resource addresses in `-target` while the matching `removed` blocks exist. In the current backend state, those targeted plans are no-ops because the retired addresses are already absent.

Feasibility conclusion:

- Targeting the old resource addresses is syntactically supported by the current Terraform CLI.
- In this current state, a targeted apply would do nothing.
- If a future backend/workspace still has the retired addresses in state, targeted apply is acceptable only after a targeted plan shows exclusively the removed-block state-forget actions, with wording equivalent to "will no longer be managed by Terraform, but will not be destroyed".
- Do not target a `removed` block itself; target the old resource addresses listed in the `from` attributes.

References:

- Terraform removed block reference: https://developer.hashicorp.com/terraform/language/block/removed
- Terraform remove from state workflow: https://developer.hashicorp.com/terraform/language/state/remove
- Terraform resource targeting tutorial: https://developer.hashicorp.com/terraform/tutorials/state/resource-targeting

## Shared SES and live SES findings

Shared SES root: `shared-ses-infra/infrastructure/aws`

Command:

```bash
terraform plan -input=false -no-color
```

Result:

- `No changes. Your infrastructure matches the configuration.`
- Current `HEAD`: `125d7e5 docs: record Namaste ses-router retirement`.

Live SES command:

```bash
aws ses describe-active-receipt-rule-set --region ap-southeast-2
```

Result:

- Active metadata name: `shared-inbound-mail-rules`
- Rule `gtd-inbound`:
  - Enabled: `true`
  - Recipient: `parse.namasteapp.tech`
  - S3 bucket: `gtd-ses-emails`
  - Lambda: `arn:aws:lambda:ap-southeast-2:352311918919:function:gtd-ses-forwarder`
- Rule `music-submission`:
  - Enabled: `true`
  - Recipient: `parse.lushauraltreats.com`
  - S3 bucket: `lush-aural-treats-ses-emails`
  - Lambda: `arn:aws:lambda:ap-southeast-2:352311918919:function:lush-aural-treats-ses-forwarder`

## Option comparison

Option A: Full-root apply now

Reject.

- Lush full-root plan already includes unrelated CodeBuild/ECS/image-tag drift.
- Lush full-root plan also fails locally because the build-notification Lambda artifact is missing.
- Namaste full-root plan cannot be reliably evaluated from this local environment without the real sensitive variables; dummy values would create misleading SSM drift.
- A full-root apply would violate the cleanup scope if it touched ECS, CodeBuild, task definitions, SSM placeholders, or Lambda packaging drift.

Option B: Targeted apply for removed-block state forget

Acceptable only conditionally, but not needed for the current state.

- Terraform accepts targeting the retired resource addresses.
- Targeted plans for both products currently return `No changes` because state already lacks the retired bindings.
- If a future state still tracks the retired bindings, this option is acceptable only if the targeted plan shows only state-forget actions and no live resource create/update/delete.

Option C: Wait until normal app deploy pipeline absorbs unrelated drift, then run full-root apply

Best fallback if future targeted plans are ambiguous or show anything besides removed-block state forget.

- This keeps SES cleanup from piggybacking unrelated product infrastructure drift.
- For Lush, the app deploy pipeline is the natural place to absorb image tag and ECS task-definition drift.
- For Namaste, use the normal deploy path with real secret variables rather than dummy local placeholders.

Option D: Manual `terraform state rm`

Reject for the normal path.

- The current pattern intentionally uses declarative `removed` blocks.
- HashiCorp documents `removed` blocks as the safer previewable workflow versus imperative state removal.
- Manual state edits should remain a last resort only if Terraform cannot plan/apply the removed-block forget cleanly in a specific backend.

## Recommended apply strategy

Current state recommendation:

1. Do not apply anything for Namaste or Lush SES cleanup now.
2. Keep the `removed` blocks in code as the declarative record of the retirement.
3. Treat the product-local SES state cleanup as already complete for the current remote states.
4. Run only pre-checks during the next apply window. If the retired addresses are still absent and targeted plans are still no-op, skip the SES apply.
5. If another workspace/backend still tracks the retired addresses, use targeted declarative apply only if its plan contains exclusively the expected state-forget actions.
6. If targeted apply is unsupported, ambiguous, or includes any non-SES changes, wait for product-root drift to clear through the normal deploy pipeline and then apply the full root.

## Exact commands for the future apply window

Pre-check state first:

```bash
cd namaste/infrastructure/terraform
terraform state list | rg 'aws_ses_(receipt_rule|receipt_rule_set|active_receipt_rule_set)' || true

cd ../../../lush-aural-treats/infrastructure
terraform state list | rg 'aws_ses_(receipt_rule|receipt_rule_set|active_receipt_rule_set)' || true
```

Namaste targeted plan, only if the retired addresses are still present in state:

```bash
cd namaste/infrastructure/terraform

terraform plan -input=false -no-color \
  -var-file=environments/prod/terraform.tfvars \
  -target=aws_ses_receipt_rule.inbound \
  -target=aws_ses_receipt_rule_set.main \
  -target=aws_ses_active_receipt_rule_set.main \
  -var="cookie_secret=${TF_VAR_cookie_secret}" \
  -var="resend_api_key=${TF_VAR_resend_api_key}" \
  -var="email_inbound_secret=${TF_VAR_email_inbound_secret}"
```

Namaste targeted apply, only if the plan shows only state-forget actions:

```bash
terraform apply \
  -target=aws_ses_receipt_rule.inbound \
  -target=aws_ses_receipt_rule_set.main \
  -target=aws_ses_active_receipt_rule_set.main \
  -var-file=environments/prod/terraform.tfvars \
  -var="cookie_secret=${TF_VAR_cookie_secret}" \
  -var="resend_api_key=${TF_VAR_resend_api_key}" \
  -var="email_inbound_secret=${TF_VAR_email_inbound_secret}"
```

Lush targeted plan, only if the retired addresses are still present in state:

```bash
cd lush-aural-treats/infrastructure

terraform plan -input=false -no-color \
  -var-file=environments/prod/terraform.tfvars \
  -target=aws_ses_receipt_rule.music_submission \
  -target=aws_ses_receipt_rule_set.main
```

Lush targeted apply, only if the plan shows only state-forget actions:

```bash
terraform apply \
  -var-file=environments/prod/terraform.tfvars \
  -target=aws_ses_receipt_rule.music_submission \
  -target=aws_ses_receipt_rule_set.main
```

Fallback full-root apply:

Use only after product-root drift is intentionally cleared or intentionally accepted by the normal app deploy pipeline. Do not use full-root apply solely for this SES cleanup while ECS, CodeBuild, image-tag, SSM, or local Lambda artifact drift remains.

## Pre-apply checks

Run before any future apply:

```bash
cd shared-ses-infra/infrastructure/aws
terraform plan -input=false -no-color

aws ses describe-active-receipt-rule-set --region ap-southeast-2

cd ../../..
cd namaste/infrastructure/terraform
terraform state list | rg 'aws_ses_(receipt_rule|receipt_rule_set|active_receipt_rule_set)' || true

cd ../../../lush-aural-treats/infrastructure
terraform state list | rg 'aws_ses_(receipt_rule|receipt_rule_set|active_receipt_rule_set)' || true
```

Required pre-apply result:

- Shared SES plan is `No changes`.
- Active SES rule set is `shared-inbound-mail-rules`.
- Live routes still include both `gtd-inbound` and `music-submission`.
- Product targeted plans show only removed-block state-forget actions, or no changes because the bindings are already absent.

## Post-apply checks

Run after any future targeted or full-root apply:

```bash
cd shared-ses-infra/infrastructure/aws
terraform plan -input=false -no-color

aws ses describe-active-receipt-rule-set --region ap-southeast-2

cd ../../..
cd namaste/infrastructure/terraform
terraform state list | rg 'aws_ses_(receipt_rule|receipt_rule_set|active_receipt_rule_set)' || true

cd ../../../lush-aural-treats/infrastructure
terraform state list | rg 'aws_ses_(receipt_rule|receipt_rule_set|active_receipt_rule_set)' || true
```

Required post-apply result:

- Shared SES still has no changes.
- Active rule set remains `shared-inbound-mail-rules`.
- `gtd-inbound` and `music-submission` remain enabled and unchanged in live SES.
- Product states still do not track the retired product-local receipt rule/rule-set addresses.

## Stop conditions

Stop immediately if any of these appear:

- A product plan proposes any create, update, delete, or replacement outside the retired SES addresses.
- A targeted plan proposes a provider delete for `gtd-rules`, `lush-aural-treats-rules`, `gtd-inbound`, or `music-submission`.
- The plan mentions `aws_ecs_service`, `aws_ecs_task_definition`, `aws_codebuild_project`, `aws_ssm_parameter`, DNS, Cloudflare, Lambda packaging, parser/app code, or active SES rule-set changes.
- Shared SES plan is not `No changes`.
- Live SES active rule set is not `shared-inbound-mail-rules`.
- Either live route is missing, disabled, or points at the wrong S3 bucket/Lambda.
- Required Namaste secret variables are unavailable for a real Namaste plan/apply.
- Local build artifacts are missing during a full-root product plan, unless the normal deploy pipeline is intentionally building them as part of a broader app deploy.

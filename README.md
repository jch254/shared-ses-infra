# shared-ses-infra

Future owner repo for shared SES inbound routing in the shared AWS account.

This repository owns the shared SES receipt rule set and receipt rules for inbound routing. It also defines the Terraform root layout, route contracts, and migration guardrails for future SES and DNS ownership.

## Why This Exists

Amazon SES has one active receipt rule set per AWS account and region. Namaste and Lush both receive inbound email in `ap-southeast-2`, so a product-local active rule set can accidentally remove the other app's route.

This repo will become the shared SES routing boundary for:

- `parse.namasteapp.tech`
- `parse.lushauraltreats.com`
- future `parse.<domain>` inbound domains

Namaste and Lush are included only at the SES routing boundary. Their app parser endpoints, authentication, allowlists, task or album creation, confirmation emails, retry behavior, outbound email providers, and product logic remain app-local.

## Model

The intended model is Option C from the audit: shared receipt-rule ownership with app-specific forwarders.

- Shared owner repo: regional SES receipt rule set, active rule set decision, route map, and later parse-domain identity/DNS ownership where safe.
- App-specific boundary: each app keeps its parser contract and forwarder behavior unless deliberately migrated later.
- Raw mail storage: one bucket per app over time; preserve existing buckets during the first migration.

## Structure

```text
infrastructure/
  aws/         # SES-region route model and future AWS SES owner resources
  cloudflare/  # parse-domain DNS model and future Cloudflare SES DNS records
```

AWS and Cloudflare roots remain separate. The AWS root should produce SES identity and route outputs later; the Cloudflare root should consume those values explicitly or via remote state when DNS ownership is migrated.

## Current Model Status

The AWS root owns the live `shared-inbound-mail-rules` receipt rule set and receipt rules with `terraform-modules` `1.6.0`.

Modeled routes:

- `gtd-inbound` for `parse.namasteapp.tech`, storing raw mail in `gtd-ses-emails` and invoking `gtd-ses-forwarder`
- `music-submission` for `parse.lushauraltreats.com`, storing raw mail in `lush-aural-treats-ses-emails` and invoking `lush-aural-treats-ses-forwarder`

The receipt rule set and receipt rules have been imported into the shared-ses-infra AWS Terraform state. A clean plan is required before any future apply.

The current Terraform roots contain:

- providers
- typed variables
- locals
- outputs
- model-only SES receipt rule modules
- commented future identity/DNS module examples
- empty `moved.tf` files for later state-safe migrations

They do not contain or manage:

- `aws_ses_active_receipt_rule_set`
- SES identities
- S3 buckets
- Lambda forwarders
- Cloudflare DNS records

`activate` remains `false` on the modeled receipt rule set, so this repo does not manage `aws_ses_active_receipt_rule_set` yet. Namaste and Lush parser endpoints, parser authentication, product behavior, and forwarder implementation details remain app-local.

## Later Verification Commands

Before any real migration or apply:

```bash
aws ses describe-active-receipt-rule-set --region ap-southeast-2
dig MX parse.namasteapp.tech
dig MX parse.lushauraltreats.com
```

Plan commands once backend configuration exists:

```bash
cd infrastructure/aws
terraform init \
  -backend-config "bucket=${REMOTE_STATE_BUCKET}" \
  -backend-config "key=shared-ses-infra/aws" \
  -backend-config "region=${AWS_DEFAULT_REGION}"
terraform plan -var-file=environments/prod/terraform.tfvars

cd ../cloudflare
terraform init \
  -backend-config "bucket=${REMOTE_STATE_BUCKET}" \
  -backend-config "key=shared-ses-infra/cloudflare" \
  -backend-config "region=${AWS_DEFAULT_REGION}"
terraform plan -var-file=environments/prod/terraform.tfvars
```

For local scaffold validation only:

```bash
cd infrastructure/aws
terraform init -backend=false -input=false
terraform validate

cd ../cloudflare
terraform init -backend=false -input=false
terraform validate
```

## Stop Conditions

Stop before applying if any plan shows:

- creation, replacement, deletion, or activation of an SES receipt rule set before all current routes are represented
- deletion or replacement of `parse.namasteapp.tech` or `parse.lushauraltreats.com` SES identities or DKIM records
- deletion or replacement of existing inbound MX records
- Cloudflare MX/TXT/DKIM records with `proxied = true`
- raw mail bucket replacement or bucket policy changes that have not been tested
- a Lambda permission change that would prevent SES from invoking the app forwarder
- a parser endpoint/auth change, especially Namaste's `x-namaste-email-secret` contract
- any Lush changes outside SES inbound routing
- any product parser or business logic being moved into this repo

First migration should model and import/move existing state. It should not recreate live SES or DNS resources.

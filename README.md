# shared-ses-infra

Owner repo for shared SES inbound routing in the shared AWS account.

This repository owns the shared SES receipt rule set and receipt rules for inbound routing. It also defines the Terraform root layout, route contracts, and migration guardrails for future SES and DNS ownership.

## Why This Exists

Amazon SES has one active receipt rule set per AWS account and region. Namaste and Lush both receive inbound email in `ap-southeast-2`, so a product-local active rule set can accidentally remove the other app's route.

This repo is the shared SES routing boundary for:

- `parse.namasteapp.tech`
- `parse.lushauraltreats.com`
- future `parse.<domain>` inbound domains

Namaste and Lush are included only at the SES routing boundary. Their app parser endpoints, authentication, allowlists, task or album creation, confirmation emails, retry behavior, outbound email providers, and product logic remain app-local.

## Model

The model is Option C from the audit: shared receipt-rule ownership with app-specific forwarders.

- Shared owner repo: regional SES receipt rule set, receipt rules, route map, and later active rule set decision plus parse-domain identity/DNS ownership where safe.
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
- imported SES receipt rule modules
- commented future identity/DNS module examples
- empty `moved.tf` files for later state-safe migrations

They do not contain or manage:

- `aws_ses_active_receipt_rule_set`
- SES identities
- S3 buckets
- S3 bucket policies
- Lambda forwarders
- Lambda permissions
- IAM roles/policies
- Cloudflare DNS records

`activate` remains `false` on the modeled receipt rule set, so this repo does not manage `aws_ses_active_receipt_rule_set` yet. Namaste and Lush parser endpoints, parser authentication, product behavior, and forwarder implementation details remain app-local.

## Ownership Boundary

shared-ses-infra owns:

- `aws_ses_receipt_rule_set` `shared-inbound-mail-rules`
- `aws_ses_receipt_rule` `gtd-inbound`
- `aws_ses_receipt_rule` `music-submission`

Namaste and Lush product stacks must not apply product-local receipt rule or receipt rule set changes that conflict with `shared-inbound-mail-rules`. In particular, do not reactivate product-only rule sets such as `gtd-rules` or `lush-aural-treats-rules` while this shared account routes both apps through `shared-inbound-mail-rules`.

Still app-local unless migrated separately:

- parse-domain SES identities and DKIM
- parse-domain Cloudflare verification, DKIM, and MX records
- raw mail buckets and bucket policies
- app-specific forwarder Lambdas
- Lambda permissions for SES invoke
- forwarder IAM roles and policies
- SSM secrets and parser endpoint configuration
- inbound parser auth, allowlists, dedupe, task/submission creation, confirmations, retries, and outbound provider choices

Future migration work:

- decide whether shared-ses-infra should later manage `aws_ses_active_receipt_rule_set`
- migrate or import parse-domain SES identities/DKIM only after state ownership is planned
- migrate or import parse-domain DNS records only after Cloudflare ownership is planned
- decide whether raw buckets, bucket policies, Lambda permissions, and forwarders remain app-local or move into shared modules
- remove or retire product-local duplicate receipt rule/rule-set resources after a reviewed state plan

## Later Verification Commands

Before any real migration or apply:

```bash
cd infrastructure/aws
terraform plan -input=false -no-color
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

Future migrations should model and import/move existing state. They should not recreate live SES or DNS resources.

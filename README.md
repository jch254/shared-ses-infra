# shared-platform

Owner repo for shared account-level platform infrastructure.

This repository owns shared SES inbound routing for private application routes, plus the shared CodeBuild notification infrastructure used by app repos. Product parser behavior, forwarder implementation, authentication, allowlists, domain behavior, confirmation emails, retries, outbound providers, and other app logic remain app-local.

## Why This Exists

Amazon SES has one active receipt rule set per AWS account and region. When multiple apps receive inbound email in the same account and SES region, a product-local active rule set can accidentally remove another app's route.

This repo is the shared platform boundary for:

- private app parse domains
- future `parse.<domain>` inbound domains
- shared CodeBuild success/failure notifications

## Structure

```text
infrastructure/
  deploy-infrastructure.bash
  terraform/
    main.tf                 # AWS shared-platform root
    variables.tf
    outputs.tf
    versions.tf
    moved.tf
    environments/prod/
    cloudflare/             # scaffold-only DNS model for future SES DNS ownership
```

`infrastructure/terraform` is the runnable AWS root. It uses the S3 state key `shared-platform`.

`infrastructure/terraform/cloudflare` is intentionally scaffold-only for now. It models future parse-domain DNS ownership, but does not currently deploy live Cloudflare records.

## Current Model

The AWS root owns the live shared receipt rule set, the active receipt rule set selector, and private app-specific SES receipt rules.

The AWS root also deploys shared CodeBuild notification infrastructure with `terraform-modules`:

- SNS topic and email subscription for CodeBuild notifications
- Lambda formatter for build success/failure events
- app-owned EventBridge subscription for the `shared-platform` CodeBuild project through the `codebuild-project` module
- outputs for app repos to target with their own EventBridge rules

App repos opt in by passing the shared formatter Lambda ARN into `codebuild-project` with `build_notifier_lambda_function_arn`; app repos keep their own EventBridge subscriptions while targeting the shared formatter Lambda.

## Build Deploys

The AWS root creates a `shared-platform` CodeBuild project in `aws_region`. It runs [buildspec.yml](buildspec.yml), which calls [infrastructure/deploy-infrastructure.bash](infrastructure/deploy-infrastructure.bash) and applies `infrastructure/terraform`.

For a fresh account or a full rebuild, bootstrap is manual once:

1. Review `infrastructure/terraform/environments/prod/terraform.tfvars`.
2. Run a local/one-off `terraform plan` and `terraform apply` from `infrastructure/terraform`.
3. Confirm the SNS email subscription if it is newly created.
4. Let the `shared-platform` CodeBuild webhook handle later AWS-root changes.

## Ownership Boundary

shared-platform owns:

- the shared SES receipt rule set
- active SES receipt rule set selection for the shared rule set
- private app-specific SES receipt rules
- the shared `shared-platform-build-notifications` SNS topic and formatter Lambda for CodeBuild project notifications
- the `shared-platform` CodeBuild project that deploys this Terraform root
- the `shared-platform` CodeBuild EventBridge notification subscription

Product stacks must not apply product-local receipt rule or receipt rule set changes that conflict with the shared inbound rule set. Do not reactivate product-only rule sets while this shared account routes multiple apps through the shared rule set.

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

- migrate or import parse-domain SES identities/DKIM only after state ownership is planned
- migrate or import parse-domain DNS records only after Cloudflare ownership is planned
- decide whether raw buckets, bucket policies, Lambda permissions, and forwarders remain app-local or move into shared modules

## Verification

To confirm shared-platform ownership is intact and live SES is healthy:

```bash
cd infrastructure/terraform
terraform init \
  -backend-config "bucket=${REMOTE_STATE_BUCKET:-jch254-terraform-remote-state}" \
  -backend-config "key=${TF_STATE_KEY:-shared-platform}" \
  -backend-config "region=${AWS_DEFAULT_REGION:-ap-southeast-4}"
terraform plan -refresh=false -var-file=environments/prod/terraform.tfvars

aws ses describe-active-receipt-rule-set --region ap-southeast-2
```

Expected live SES result: the shared inbound rule set is active, private app route rules are enabled, scan is enabled, TLS is `Optional`, raw mail S3 actions are present, and Lambda invocation type is `Event`.

Optional DNS sanity:

```bash
dig MX parse.namasteapp.tech
dig MX parse.lushauraltreats.com
```

For local scaffold validation only:

```bash
cd infrastructure/terraform
terraform init -backend=false -input=false
terraform validate

cd cloudflare
terraform init -backend=false -input=false
terraform validate
```

## Stop Conditions

Stop before applying if any plan shows:

- creation, replacement, deletion, or deactivation of the shared SES receipt rule set
- activation of any receipt rule set other than `shared-inbound-mail-rules`
- deletion or replacement of existing private app SES receipt rules before their replacement routes are represented
- deletion or replacement of private app parse-domain SES identities or DKIM records
- deletion or replacement of existing inbound MX records
- Cloudflare MX/TXT/DKIM records with `proxied = true`
- raw mail bucket replacement or bucket policy changes that have not been tested
- a Lambda permission change that would prevent SES from invoking an app forwarder
- a private app parser endpoint/auth change
- any private app changes outside SES inbound routing
- any product parser or business logic being moved into this repo

Future migrations should model and import/move existing state. They should not recreate live SES or DNS resources.

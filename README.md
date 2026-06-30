# Idealo Assignment — S3 Upload Validator
[![Pipeline status](https://github.com/AliElKhatteb/Idealo_Assignment/actions/workflows/terraform.yml/badge.svg?branch=main)](https://github.com/AliElKhatteb/Idealo_Assignment/actions/workflows/terraform.yml)

A Terraform module that provisions a secure S3 bucket for file uploads and an
event-driven AWS Lambda function that validates each uploaded object against
an allow-list of file extensions and a set of required metadata keys.
Infrastructure is deployed through a GitHub Actions CI/CD pipeline
(validate → plan → apply) with remote, encrypted Terraform state in S3.

## Architecture

![Architecture diagram](docs/s3_upload.drawio.svg)

- **S3 bucket** — stores uploaded files. Public access is fully blocked,
  encryption at rest is enforced, versioning is on, and objects automatically
  transition to Glacier Instant Retrieval after 30 days and expire after 365.
- **Lambda function** — triggered on every s3 object upload event. It
  reads the object's metadata, checks the file
  extension against an allow-list, and checks that all required metadata
  keys are present. The result (`COMPLIANT` / `NON_COMPLIANT` with a list of
  violations) is written as a structured JSON log line to CloudWatch.
- **IAM** — the Lambda's execution role is scoped to exactly what it needs:
  `s3:GetObject` / `GetObjectAttributes` / `HeadObject` on the upload
  bucket only, and `logs:CreateLogStream` / `PutLogEvents` on its own log
  group only. No wildcard resources following Principle of least privilege.
- **CI/CD** — a three-stage GitHub Actions workflow: validate Terraform
  formatting/syntax, plan against the `dev` environment, then apply (on
  pushes to `main`) using the artifact produced by the plan stage, so what
  gets applied is exactly what was planned.

## Repository layout

```
modules/file_upload_bucket/   Reusable Terraform module
  main.tf                     S3 bucket, versioning, encryption, lifecycle
  lambda.tf                   Lambda function + packaging + invoke permission
  iam.tf                      Execution role, scoped policy, log group
  notifications.tf            S3 → Lambda event notification
  variables.tf / outputs.tf
  lambda/validator.py         Validation logic

test-deployment/               Example "dev" deployment of the module
  main.tf                     Module call with dev-specific inputs
  variables.tf / provider.tf
  backend.tf                  Partial S3 backend config (filled via -backend-config)
  envs/dev.tfvars             Variable values for the dev environment
  envs/backend_dev.hcl        Backend config (state bucket/key/region)

.github/workflows/terraform.yml   CI/CD pipeline (validate / plan / apply)
test_files/                       Sample files used for manual smoke testing
```

## Configuration

| Variable             | Description                                                | Example                    |
|----------------------|-------------------------------------------------------------|------------------------------|
| `name`               | Prefix used for all resources created by the module          | *(required)*                |
| `allowed_extensions` | File extensions accepted by the validator                    | `jpg`, `jpeg`, `png`, `pdf` |
| `required_metadata`  | Object metadata keys that must be present on every upload    | `customer-id`               |
| `tags`               | Tags applied to taggable resources                            | `{}`                        |

The `test-deployment` example overrides these for the `dev` environment via
`envs/dev.tfvars`, requiring `customer-id` and `document-type` metadata and
allowing `pdf`, `png`, and `jpg` uploads.

## Deploying

### 1. One-time: create the Terraform state backend

The state bucket is created out-of-band, before any `terraform init`, since
Terraform can't manage the bucket it stores its own state in:

```bash
aws s3api create-bucket \
  --bucket terraform-state-idealo-dev \
  --region eu-central-1 \
  --create-bucket-configuration LocationConstraint=eu-central-1

aws s3api put-bucket-versioning \
  --bucket terraform-state-idealo-dev \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket terraform-state-idealo-dev \
  --server-side-encryption-configuration '{
    "Rules": [
      { "ApplyServerSideEncryptionByDefault": { "SSEAlgorithm": "AES256" } }
    ]
  }'
```

### 2. Update `test-deployment/envs/dev.tfvars`

Configure the deployment by editing the following values:

```hcl
name                = "idealo-assignment-dev-uploads"
environment         = "dev"
allowed_extensions  = ["pdf", "png", "jpg"]
required_metadata   = ["customer-id", "document-type"]
```

### 3. Init, plan, apply

```bash
cd test-deployment
terraform init -backend-config=envs/backend_dev.hcl
terraform plan  -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars
```

### 4. CI/CD

Pushing to `main` or opening a pull request runs the GitHub Actions workflow:

1. **Validate** — `terraform fmt -check` and `terraform validate`
2. **Plan** — `terraform plan` (uploaded as a workflow artifact)
3. **Apply** — On `main`, applies the saved plan to ensure the deployed infrastructure matches the reviewed plan.

The pipeline expects `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and
`AWS_REGION` to be configured as environment secrets in Github.

## Manual smoke test

```bash
export BUCKET=<your-bucket-name>

echo "hello world"     > test_files/valid.pdf
echo "malware payload" > test_files/invalid.exe
echo "test file"       > test_files/missing_metadata.pdf

# Valid: allowed extension + all required metadata present
aws s3 cp test_files/valid.pdf s3://$BUCKET/valid.pdf \
  --metadata customer-id=123,document-type=invoice

# Invalid: disallowed extension
aws s3 cp test_files/invalid.exe s3://$BUCKET/invalid.exe

# Invalid: missing required metadata
aws s3 cp test_files/missing_metadata.pdf s3://$BUCKET/missing_metadata.pdf
```

Check the Lambda's CloudWatch log group (`/aws/lambda/<name>-validator`) for
a `COMPLIANT` result on `valid.pdf` and `NON_COMPLIANT` results with the
specific violations listed for the other two.

## Architecture Decisions

**Event trigger: S3 → Lambda.**  
Direct S3 notifications provide immediate validation without polling or additional infrastructure. I considered EventBridge, but with only a single consumer (the validator), it would add unnecessary complexity. It would become a better choice if multiple services needed to consume upload events.

**Per-object validation.**  
Each upload is validated as it arrives, providing immediate feedback and a clear log entry. A scheduled scan would reduce Lambda invocations but delay detection, which doesn't fit the requirement.

**Detect and log, not detect and fix.**  
The Lambda writes structured `COMPLIANT` or `NON_COMPLIANT` log entries with any violations. It intentionally performs no remediation (deletion, tagging, or moving files), keeping the solution simple, and aligned with the assignment.

**Validation rules as Lambda environment variables, not hardcoded.**
`ALLOWED_EXTENSIONS` and `REQUIRED_METADATA` are module variables passed
through to the function's environment rather than hardcoded in
`validator.py`. making it enough for different teams to plug in their own file-type and metadata requirements without touching code.

**IAM scoped to exactly what the Lambda needs.**
The execution role can `GetObject` / `GetObjectAttributes` / `HeadObject`
on the upload bucket only, and write logs to its own log group only — no
wildcard resources, no bucket-wide write or delete access. Since the
function only inspects metadata and never modifies objects, it has no
write/delete permissions on the bucket at all.

**What was intentionally left out:**
- Content-based validation (parsing files) — the requirements asks about format/metadata, not deep inspection.
- Remediation/alerting (SNS, EventBridge) — explicitly out of scope per the requirements.

## Production Readiness

Specific changes before running this with real production data:

- **Failure handling and alerting.** Today, neither invocation failures nor NON_COMPLIANT results reach a person. I currently rely on Lambda's native async retry, but to make this production-ready, we need to configure a Lambda Destination (on_failure) to automatically forward the exhausted error payload to an SNS topic. From there, SNS will send an email to the responsible team so they can take action.
- **State locking.** The S3 backend has versioning and encryption but no
  DynamoDB lock table (or `use_lockfile` on Terraform ≥1.10). With a single
  CI/CD pipeline as the only writer this is low risk today, but real
  production use with multiple contributors running `terraform apply`
  locally needs locking to prevent concurrent state corruption.
- **Automated tests for the Lambda.** `validator.py`'s correctness is
  currently verified by the manual `aws s3 cp` smoke test in this README.
  Before production I'd add a `pytest` suite that invokes `lambda_handler`
  with mocked S3 events covering: valid file, disallowed extension, missing metadata, multiple violations, and a `HeadObject` failure — and run it in the CI `validate` stage.
- **CI/CD environment.** The current pipeline only deploys
  `dev`. Production use needs a `prod.tfvars` + `backend_prod.hcl` pair, an
  explicit approval gate on the `apply` job for prod (GitHub Environments
  support required reviewers natively).
- **Multi-account.** Out of scope for this exercise per the single-account constraint. If extended to multi-account, I'd keep each team's resources fully isolated within their own account — this fits a model where each account represents its own environment, like dev, QA, and prod.
- **Cost/lifecycle validation at scale.** The Glacier IR transition and
  365-day expiration are correct per the requirements since nobody will access it after 30 days, but at "hundreds of uploads per minute" sustained, I'd want a CloudWatch billing alarm on this bucket, otherwise this could incure high costs.

## AI Tooling

**Tools used:** ChatGPT (chat-based) for drafting and reviewing the Terraform module, the Lambda function, and the GitHub Actions pipeline; used throughout the assignment rather than for one isolated part. Claude was used afterward to review the finished solution against the assignment requirements and help write this README.

**Where the AI's first suggestion was wrong or suboptimal:**

1. **IAM policy used `Resource = "*"`.** The first draft of the Lambda's
   IAM policy granted S3 read permissions with a wildcard resource instead
   of scoping to the specific upload bucket's ARN. I changed it to
   `"${aws_s3_bucket.uploads.arn}/*"` and similarly scoped the CloudWatch
   Logs permissions to the function's own log group ARN. Wildcard resources
   are an easy default for an AI to reach for because they "just work" in
   any context, but they directly contradict least-privilege, which
   matters more here than convenience.
2. **Unguarded `head_object` call.** The AI's first version of
   `validator.py` called `s3.head_object(Bucket=bucket, Key=key)` directly
   with no error handling. If the object is deleted or made inaccessible
   between the S3 event firing and the Lambda running, this throws an
   unhandled `ClientError` with no context in the logs. I wrapped it in
   `try/except` with `logger.exception` (to get the full traceback in
   CloudWatch) before re-raising, so failures are diagnosable instead of
   showing up as an opaque stack trace.

**A prompt that didn't work well:**
When CI started failing with:
```
Error: Failed to install provider
Error while installing hashicorp/archive v2.8.0: error checking signature:
openpgp: key expired
```
I asked the AI directly what was causing it and how to fix it. It offered
several plausible-sounding but incorrect explanations (suggesting a fresh
`terraform init` cache, or a corrupted lock file) and none of the
suggested fixes worked, because the AI didn't have visibility into the
actual upstream cause: a HashiCorp GPG signing key used by the Terraform
registry had expired, a known issue affecting many users at the time
(tracked in
[hashicorp/terraform#38418](https://github.com/hashicorp/terraform/issues/38418)).
I found the real cause and fix by searching GitHub issues directly instead
of continuing to iterate on the prompt and waste time.


**Take: when AI tooling helps vs. gets in the way, for infrastructure
work.**

AI is great for generating boilerplate like Terraform code, and useful as a second pair of eyes to spot unhandled failures. However, it gets in the way with stale knowledge on live errors and a tendency to generate insecure, over-permissioned defaults just to make code run—so you need to check carefully what it writes.

Ultimately, AI is just a tool that accelerates the work; it doesn't replace engineering knowledge. The best pattern is letting AI write the fast first boilerplate, then using your own AWS experience to manually review and adjust the code according to your needs.
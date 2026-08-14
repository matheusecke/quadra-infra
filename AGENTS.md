# Quadra Infrastructure Instructions

`AGENTS.md` and `CLAUDE.md` intentionally contain the same instructions. Keep
them synchronized.

## Scope and Sources of Truth

- Treat this repository as infrastructure-only unless cross-repository work is
  explicitly requested.
- Terraform manages AWS infrastructure. GitHub Actions builds, publishes, and
  deploys application versions. Never deploy applications with Terraform.
- Preserve the Docker Compose development environment unless explicitly asked
  to change it.
- Read before proposing infrastructure changes:
  1. [`README.md`](README.md)
  2. [`docs/ROADMAP.md`](docs/ROADMAP.md) — architecture and trade-offs
  3. [`docs/aws-setup-and-access.md`](docs/aws-setup-and-access.md) — confirmed
     operational state and access
  4. [`docs/aws-ci-cd-flow.md`](docs/aws-ci-cd-flow.md) — CI/CD strategy
  5. Existing files in [`terraform/`](terraform/)
- Do not silently override recorded decisions. Explain conflicts and ask for
  direction.

## Language

- Use English for HCL identifiers, code comments, branches, commits, and these
  instruction files.
- Preserve each document's existing language: the root README is English and
  the current `docs/` infrastructure documents are Portuguese.

## Operating Rules

Infrastructure work is manual while Terraform is being learned and established.

- Do not run any Terraform command unless the user authorizes that exact step.
- Do not run AWS commands that mutate resources unless explicitly authorized.
- For read-only AWS checks, explain the required information first and prefer
  giving the command to the user to run.
- Do not modify Terraform, advance provisioning stages, or commit unless asked.
- Always review a fresh plan before apply. Stop for explicit confirmation before
  changes involving cost, IAM, networking, public access, state, replacement,
  deletion, downtime, or data loss.
- `terraform destroy` is not part of the normal workflow.

For every proposed command, state briefly:

- why it is needed;
- what it reads or changes;
- risks and possible cost;
- expected output;
- what must be verified before continuing.

Follow this flow:

```text
inspect → explain → propose one step → user executes → validate → document
```

## Architecture Decisions

- AWS region is `us-east-1`.
- Start with one environment, `production`, used as the TCC demo environment.
- Keep flat `.tf` files in `terraform/`. No custom modules, Terragrunt, or
  workspaces until a concrete need is discussed.
- Derive environment-specific names from `environment`; do not hardcode `prod`.
- ECR and the Terraform state bucket are shared across possible future
  environments and remain outside the environment prefix.
- Remote state uses S3 with encryption, versioning, and native lockfiles. Treat
  backend changes as sensitive state operations.
- The planned low-cost network uses public ECS task subnets with
  `assign_public_ip = true`, no NAT Gateway, and inbound access only from the ALB
  security group. RDS remains private and never publicly accessible.
- Maintain and pause infrastructure instead of routinely destroying it. ECS may
  use `desired_count = 0`; stopping RDS requires an operational mechanism
  outside Terraform.

## Terraform Conventions

- Keep the root configuration explicit and simple. Add abstractions only for a
  demonstrated need.
- Use `versions.tf`, `provider.tf`, `variables.tf`, `main.tf`, and `outputs.tf`
  until a focused resource split improves clarity.
- Pin Terraform/provider compatibility and commit `.terraform.lock.hcl`.
- Use lowercase snake_case identifiers, singular names for single values, and
  plural names for collections. Do not repeat the resource type unnecessarily.
- Give every variable and output a clear `description`; use explicit types.
- Order variable fields as `description`, `type`, `default`, then `validation`.
- Prefer resource references and data sources over copied AWS IDs.
- Avoid premature `count`, `for_each`, dynamic blocks, modules, and clever
  expressions.
- Follow existing naming and tagging conventions. Use two-space indentation and
  standard `terraform fmt` output.
- Protect durable resources with lifecycle rules when deletion is exceptional.

## State, Access, and Secrets

- Treat state and saved plans as sensitive.
- Never commit `.terraform/`, `*.tfstate`, state backups, saved plans, secret
  `.tfvars`, backend credentials, or temporary authentication data.
- Never record passwords, MFA material, access keys, secret keys, session
  tokens, authorization codes, or application secrets. Sanitize outputs before
  documenting them.
- Human access uses `aws login`, profile `quadra-admin`, and the non-root IAM
  user documented in `aws-setup-and-access.md`.
- Do not hardcode the local profile or credentials in Terraform. Supply local
  authentication externally through `AWS_PROFILE`.
- GitHub Actions must use OIDC and dedicated least-privilege IAM roles with
  temporary credentials. Never reuse the human identity or permanent AWS keys.

## Validation and Documentation

- When authorized, validate progressively: `terraform fmt`, `validate`, then
  `plan`.
- If a plan may be applied, save it with `-out`, inspect it with `terraform show`,
  and apply only that reviewed file after explicit approval.
- Do not use `-auto-approve` or treat `-target` as a normal workflow shortcut.
- A valid configuration does not prove a safe plan. Review create, update,
  replace, and destroy actions separately.
- Never claim validation without observed command output. Attribute commands run
  by the user to the output they provided.
- Record only confirmed operational facts in `aws-setup-and-access.md`.
- Keep architecture and trade-offs in `ROADMAP.md`, and pipeline evolution in
  `aws-ci-cd-flow.md`. Never describe planned resources as provisioned.

## Commits

- Keep commits focused and do not create them unless explicitly requested.
- Do not add `Co-authored-by`, `Signed-off-by`, `Generated-by`, or equivalent
  authorship or tool-identification metadata.

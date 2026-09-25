# NovaHealth Terraform Landing Zone — Architecture & CI/CD Guide

This document explains what this repository does, how it is organized, the
CI/CD pipeline added under [.github/workflows](.github/workflows), and a set
of concrete recommendations to improve the structure going forward.

## 1. What this repository does

This is a **Terraform Azure Landing Zone** for a fictitious healthcare
company, "NovaHealth". It codifies an enterprise-scale, multi-subscription
Azure environment following the [Cloud Adoption Framework (CAF)](https://learn.microsoft.com/azure/cloud-adoption-framework/) pattern:
a central Management Group hierarchy, subscription vending, governance
(policy + RBAC), networking (hub-based), observability, cost control
(FinOps), and optional workload accelerators (jumpbox, RAG infrastructure,
test VM).

It is deployed twice, once per physical region/scope:

- **Primary** — [environments/primary](environments/primary) — `swedencentral`
- **Disaster Recovery (DR)** — [environments/dr](environments/dr) — `francecentral`

Both environments consume the same reusable modules under
[modules/](modules), but wire them up independently, each with its own
Terraform remote state file, subscriptions, and variables.

### 1.1 Layered deployment model

The same 7-layer sequence appears in the root [main.tf](main.tf) (legacy/demo
entry point) and in [environments/primary/main.tf](environments/primary/main.tf)
/ [environments/dr/main.tf](environments/dr/main.tf) (the real, per-environment
entry points):

| Layer | Module | Purpose |
|---|---|---|
| 1 | [modules/management_groups](modules/management_groups) | Management Group hierarchy (root, platform, landing zones, security) |
| 2 | [modules/subscriptions](modules/subscriptions) | Associates existing ("BYOS" bring-your-own-subscription) subscriptions to Management Groups; supports a "student mode" (single subscription) vs. "enterprise mode" (5 real subscriptions: connectivity, identity, management, production, data_ai) |
| 3 | [modules/resource_groups](modules/resource_groups) | Centralized resource group provisioning across the 5 physical subscriptions, aware of `primary`/`dr` deployment scope |
| 4 | [modules/policy](modules/policy) | Azure Policy definitions/initiatives/assignments for cost control, data, identity, network security, networking, security, and tagging |
| 5 | [modules/rbac](modules/rbac) | Role assignments at Management Group / subscription scope, including a CI/CD service principal |
| 6 | [modules/networking](modules/networking) | Hub VNet, subnets, NSGs, routes, Azure Firewall, DNS, cross-region peering |
| 7 | [modules/finops](modules/finops) | Budgets/alerts and cost-control notifications |
| 8 (env only) | [modules/observability](modules/observability) | Diagnostic settings + metric alerts wired to networking resources (firewall, App Gateway, VPN GW, Bastion, DNS resolver) |

Additional standalone workload modules exist but are **not currently wired
into any environment's `main.tf`**: [modules/jumpbox](modules/jumpbox),
[modules/rag_infrastructure](modules/rag_infrastructure),
[modules/test_vm](modules/test_vm). They look like accelerators meant to be
opted into per-workload rather than part of the core landing zone.

### 1.2 State & provider design

- Each environment has its own `azurerm` backend key
  (`primary.tfstate` / `dr.tfstate`), now using **partial backend
  configuration** (see §2) so the storage account/resource group/container
  are injected at `terraform init` time by CI rather than hardcoded.
- Both environments declare 5 aliased `azurerm` providers
  (`connectivity`, `identity`, `management`, `production`, `data_ai`), one
  per physical subscription, passed explicitly into child modules via the
  `providers = { ... }` map — this is the correct pattern for
  multi-subscription Terraform.

### 1.3 Local `terraform init` — backend.hcl

Because the backend block only declares `key` (partial config), running
`terraform init` locally with no flags fails with:

```
Error: One of access_key, sas_token, use_azuread_aauth and resource_group_name must be specified
```

To init locally, copy the committed example file per environment and fill
in the real values, then point `init` at it:

```bash
cd environments/dr        # or environments/primary
cp backend.hcl.example backend.hcl   # backend.hcl is gitignored
az login
terraform init -backend-config=backend.hcl
```

[environments/primary/backend.hcl.example](environments/primary/backend.hcl.example)
and [environments/dr/backend.hcl.example](environments/dr/backend.hcl.example)
both set:

```hcl
resource_group_name  = "rg-terraform-tfm-state"
storage_account_name = "sttfmstateshared"
container_name       = "terraform-state"
use_azuread_auth     = true
```

`use_azuread_auth = true` is what fixes the error above: it tells the
`azurerm` backend to authenticate to the state storage account with your
logged-in identity (Azure CLI locally, OIDC in CI) instead of requiring an
`access_key`/`sas_token`. The same flag is passed by CI via
`-backend-config="use_azuread_auth=true"` in both
[terraform-plan.yml](.github/workflows/terraform-plan.yml) and
[terraform-apply.yml](.github/workflows/terraform-apply.yml).

**Required RBAC:** the identity running `init` (your user, or the CI
service principal) needs the **Storage Blob Data Contributor** role on the
state storage account — a subscription-level Contributor role alone does
not grant blob data-plane access.

## 2. Structural findings & recommendations

### 2.1 Fixed as part of this change
- **[environments/dr/providers.tf](environments/dr/providers.tf) had no
  `backend` block at all**, meaning a `dr` apply would have silently used
  local state (or failed to share state with teammates/CI), while
  `primary` used a fully hardcoded remote backend. Both now use a
  consistent **partial backend config** (`key` only in code; account/RG/
  container name supplied via `-backend-config` flags in CI). This removes
  the asymmetry and avoids hardcoding infra names in version control.
- **Local `terraform init` failing with "One of access_key, sas_token,
  use_azuread_aauth and resource_group_name must be specified"** — added
  `backend.hcl.example` per environment (§1.3) plus `use_azuread_auth =
  true` in CI's `-backend-config`, so both local devs and CI authenticate
  to the state storage account via Azure AD identity instead of an access
  key. `backend.hcl` (the real, filled-in copy) is gitignored.
- **`.tfvars` injected from GitHub secrets in CI** —
  [terraform-plan.yml](.github/workflows/terraform-plan.yml) and
  [terraform-apply.yml](.github/workflows/terraform-apply.yml) each have a
  step that materializes `primary.tfvars`/`dr.tfvars` from a
  `TFVARS_PRIMARY`/`TFVARS_DR` repo secret right before `plan`/`apply`,
  then delete it in a `Cleanup sensitive files` step that runs `if:
  always()` (after apply, not before, so the file exists when needed).
  This lets the same `-var-file` pattern work in CI without ever
  committing subscription IDs to the repo.

### 2.2 Recommended follow-ups (not applied automatically — review first)

1. **Root main.tf/providers.tf vs environments/** — [main.tf](main.tf),
   [providers.tf](providers.tf), [variables.tf](variables.tf) at the repo
   root duplicate ~90% of [environments/primary](environments/primary). The
   root version also has a leftover `data_ia` (typo) provider alias and no
   `deployment_scope`-aware backend. Recommend either:
   - deleting the root `*.tf` files and treating `environments/*` as the
     only deployable roots, or
   - turning the root files into a clearly-marked example/reference that is
     never `terraform apply`'d (e.g. move to `examples/legacy-single-sub/`).

2. **Inconsistent formatting** — root `*.tf` files use spaces while
   `environments/*/*.tf` use tabs for indentation. Run `terraform fmt
   -recursive` (now enforced in CI, see §3) and commit the result once.

3. **Hardcoded notification emails** — `finops@novahealth.com` and
   `ops-alerts@novahealth.com` are hardcoded in [main.tf](main.tf) /
   [environments/primary/main.tf](environments/primary/main.tf) /
   [environments/dr/main.tf](environments/dr/main.tf) instead of being
   variables. Recommend promoting these to `variable` blocks with
   per-environment `.tfvars` overrides.

4. **Secrets-shaped variables with empty-string defaults** —
   `cicd_service_principal_object_id`, `student_subscription_id`, and the
   enterprise subscription ID variables all default to `""`. Defaults on
   sensitive/identifying values encourage accidental applies with blank
   IDs; consider removing defaults (forcing explicit `-var-file`) and
   marking subscription ID variables `sensitive = true`.

5. **No `.tfvars` files or `.tfvars.example` committed** — since
   `*.tfvars` is (correctly) gitignored for secrets, there's no
   `*.tfvars.example` showing which variables an operator must set per
   environment. Recommend adding
   `environments/primary/primary.tfvars.example` and
   `environments/dr/dr.tfvars.example` with placeholder values.

6. **No module-level README/versions.tf** — modules under
   [modules/](modules) don't declare their own `required_providers`
   version constraints (only root/environment `providers.tf` do) and have
   no per-module README documenting inputs/outputs beyond
   `variables.tf`/`outputs.tf`. Consider `terraform-docs` generated READMEs
   per module (can be added as a CI job).

7. **Unwired modules** — [modules/jumpbox](modules/jumpbox),
   [modules/rag_infrastructure](modules/rag_infrastructure), and
   [modules/test_vm](modules/test_vm) are not referenced from any
   `main.tf`. If they're meant to be optional workloads, document that
   explicitly (e.g. in each module's own README) so it's clear they're not
   dead code.

8. **No CI previously existed** — there was no `.github/workflows`
   directory at all; this PR adds the pipeline described below.

## 3. CI/CD pipeline (added in this change)

Three GitHub Actions workflows were added under
[.github/workflows](.github/workflows):

### [terraform-validate.yml](.github/workflows/terraform-validate.yml) — on every PR/push touching `*.tf`
- `terraform fmt -check -recursive` — fails the build on formatting drift.
- `terraform validate` — run per-stack (both environments + every module
  individually, via a matrix) with `-backend=false`, so no cloud
  credentials are needed just to validate syntax/types.
- `tflint --recursive` — naming conventions, unused declarations, typed
  variables, documented variables/outputs, using
  [.tflint.hcl](.tflint.hcl) (includes the `azurerm` ruleset).
- `tfsec` — static security scan (soft-fail initially, so it reports
  without blocking merges until the team is ready to enforce it).

### [terraform-plan.yml](.github/workflows/terraform-plan.yml) — on PRs touching `environments/**` or `modules/**`
- Matrix over `primary` and `dr`.
- Authenticates to Azure via **OIDC** (`azure/login`, no long-lived client
  secret stored in GitHub).
- `terraform init` with partial backend config supplied from repo secrets.
- `terraform plan` and posts the plan output as a PR comment (per
  environment) so reviewers see the exact infra diff before approving.

### [terraform-apply.yml](.github/workflows/terraform-apply.yml) — manual dispatch only
- `workflow_dispatch` input to pick `primary` or `dr`.
- Uses a GitHub **Environment** named after the target (`primary`/`dr`) —
  configure required reviewers on these Environments in
  *Settings → Environments* to enforce manual approval gates before any
  `apply` runs, which is the standard safe pattern for infra pipelines.
- Re-plans and applies with `-auto-approve` only after the plan step and
  only inside the approved job, uploading the applied plan as an artifact
  for audit purposes.

### Required repository/organization secrets

| Secret | Purpose |
|---|---|
| `AZURE_CLIENT_ID` | App registration (federated credentials / OIDC) client ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Subscription used for the `azurerm` login context |
| `TF_STATE_RESOURCE_GROUP` | RG containing the shared state storage account |
| `TF_STATE_STORAGE_ACCOUNT` | Storage account name for remote state |
| `TF_STATE_CONTAINER` | Blob container name for remote state |
| `TFVARS_PRIMARY` | Full contents of `primary.tfvars`, injected at runtime for the `primary` environment |
| `TFVARS_DR` | Full contents of `dr.tfvars`, injected at runtime for the `dr` environment (needed once `dr` is enabled in the plan matrix) |

You'll also need to set up **federated credentials** on the Azure AD app so
it trusts GitHub OIDC tokens for this repo/branch (`repo:<org>/<repo>:ref:refs/heads/main`
for apply, and `repo:<org>/<repo>:pull_request` for plan), avoiding any
Azure client secret being stored in GitHub at all.

## 4. Suggested next steps

1. Run `terraform fmt -recursive` once locally/in CI and commit the diff.
2. Decide the fate of the root `main.tf`/`providers.tf`/`variables.tf`
   (merge into `environments/primary` docs or move to an `examples/`
   folder).
3. Add `*.tfvars.example` files per environment.
4. Configure the `primary` and `dr` GitHub Environments with required
   reviewers before enabling `terraform-apply.yml` for real deployments.
5. Once `tfsec` findings are triaged, remove `soft_fail: true` to make the
   security gate blocking.

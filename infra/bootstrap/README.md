# Terraform state bootstrap

This sub-config provisions the Azure resources that hold Terraform remote state for the rest of `infra/`. It is **run once per state environment** (typically once total) with **local state** — its own outputs feed the `terraform init -backend-config=...` flags used by the parent config.

There are two supported ways to run it:

1. **CI-driven (recommended for restricted environments such as Gov / NVD-isolated workstations):** dispatch the [`terraform-bootstrap`](../../.github/workflows/terraform-bootstrap.yml) GitHub Actions workflow.
2. **Local (operator workstation):** run `terraform apply` against this directory manually.

## Option 1 — CI-driven bootstrap (recommended)

Use this path when operators cannot run `az login` / `terraform` from their local machine (e.g. NVD-isolated workstations, locked-down Gov endpoints).

### Prerequisites

- `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` repo **secrets** are configured for OIDC federated identity (see `docs/DEPLOYMENT.md` §15).
- A GitHub **Environment** with the same name as the `environment_name` input (e.g. `shared`, `dev`, `prod`) exists, optionally gated by required reviewers.
- The federated CI service principal has, **at the subscription scope** for the target subscription:
  - `Contributor` (to create the RG / storage account / container), and
  - `User Access Administrator` (only if `ci_principal_id` is supplied, so the workflow can grant `Storage Blob Data Contributor` on the state SA).

### Trigger

1. GitHub UI → **Actions** → **terraform-bootstrap** → **Run workflow**.
2. Fill in the inputs:
   - `environment_name` — state environment suffix; usually `shared` for the whole platform, or `dev` / `prod` if you want isolated backends.
   - `location` — Azure region for the state RG/SA (e.g. `eastus2`, `usgovvirginia`).
   - `ci_principal_id` — object ID of the CI service principal to grant data-plane access to the state SA. Leave blank to skip.
   - `azure_environment` — `public` or `usgovernment`. Selects the right Azure cloud for both the `azurerm` provider and `azure/login`.

### What the workflow does

- Restores the previous bootstrap state from the `bootstrap-tfstate-<env>-*` GitHub Actions cache, if any.
- Runs `terraform init` with local state (no backend by design — see [Why local state for bootstrap?](#why-local-state-for-bootstrap)).
- For each of `azurerm_resource_group.state`, `azurerm_storage_account.state`, `azurerm_storage_container.tfstate`: if the resource is missing from state, attempts `terraform import` against a deterministically-computed Azure resource ID. This makes the workflow self-healing if the cache is evicted (default 7-day idle) or the run is the very first bootstrap.
- Runs `terraform plan` then `terraform apply -auto-approve` with the workflow inputs as `-var` flags.
- Persists the updated state file back into the cache under a per-run key.
- Prints the three values you need to set as GitHub Actions repository **variables** into the job summary as a copy-paste-ready table.

### After it finishes

Copy the values from the workflow summary into **Settings → Secrets and variables → Actions → Variables**:

| Variable | Source |
| --- | --- |
| `TFSTATE_RESOURCE_GROUP` | `state_resource_group_name` output |
| `TFSTATE_STORAGE_ACCOUNT` | `state_storage_account_name` output |
| `TFSTATE_CONTAINER` | `state_container_name` output |

Those three variables are consumed by `terraform.yml` and `terraform-destroy.yml` to wire up the parent config's `azurerm` backend.

### Re-runs and state recovery

The workflow is idempotent. Re-dispatching it for the same `environment_name`:

- **Within ~7 days of the previous run:** the state cache is hit, no imports are needed, `terraform apply` is a no-op unless inputs changed.
- **After cache eviction or for a fresh repo clone:** the cache miss is handled by the import step — existing Azure resources are pulled back into state and `apply` resumes from there.

One known caveat: `azurerm_role_assignment.ci_state_writer` has an Azure-generated GUID that is **not** importable from inputs alone. If the cache has been evicted **and** the role assignment still exists in Azure, a re-run with the same `ci_principal_id` will fail with `RoleAssignmentExists` (409). Workarounds:

- Re-run with `ci_principal_id` blank (the existing role assignment is left in place).
- Or, from a runner with `az` available (e.g. a one-off `workflow_dispatch` with a debug step), look up the role assignment with `az role assignment list --assignee <principal>` and import it manually with `terraform import azurerm_role_assignment.ci_state_writer /subscriptions/.../roleAssignments/<guid>`.

## Option 2 — Local bootstrap

Use this path on an operator workstation with `az` and `terraform` installed and unrestricted access to the target Azure cloud.

```bash
cd infra/bootstrap
az login                              # az cloud set --name AzureUSGovernment first, for Gov
az account set --subscription <subscription-id>

terraform init
terraform apply \
  -var environment_name=shared \
  -var location=eastus2 \
  -var ci_principal_id=<github-actions-sp-object-id>
```

Capture the outputs:

```bash
terraform output -raw state_resource_group_name
terraform output -raw state_storage_account_name
terraform output -raw state_container_name
terraform output -raw init_backend_config_snippet
```

Set the corresponding GitHub Actions repository variables (not secrets — these aren't sensitive):

| Variable | Value |
|---|---|
| `TFSTATE_RESOURCE_GROUP` | `terraform output -raw state_resource_group_name` |
| `TFSTATE_STORAGE_ACCOUNT` | `terraform output -raw state_storage_account_name` |
| `TFSTATE_CONTAINER` | `terraform output -raw state_container_name` |

The bootstrap state file (`terraform.tfstate`) lives **locally** on the operator's machine. Treat it like any other secret: do **not** commit it. The parent `.gitignore` excludes it.

## Why local state for bootstrap?

Chicken-and-egg: storing the bootstrap state in the storage account it just created would prevent the very first `apply`. Local state breaks the loop. Once bootstrap is applied the file is rarely needed again — only when rotating the state SA.

In the CI-driven flow we don't ship the local `terraform.tfstate` anywhere durable — we persist it inside the GitHub Actions cache and rely on the `terraform import` step to rehydrate from Azure if the cache is ever evicted.

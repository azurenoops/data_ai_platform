# Azure RBAC request — Data + AI + MCP platform deployment

**Audience:** Azure Government subscription Owner / cloud admin
**Requested by:** Platform team
**Purpose:** Grant the CI service principal the minimum rights needed to run
`terraform apply` for this repo unattended via GitHub Actions.

## TL;DR — what to grant

Grant the CI service principal **two** built-in roles on **the target
subscription** (Gov: `usgovvirginia`):

| Role | Why |
|---|---|
| **Contributor** | Create / update / delete Azure resources in the subscription. |
| **User Access Administrator** | Write the ~18 role assignments the Terraform creates between workload-managed identities and the storage / Search / Foundry / Key Vault resources it also creates. |

Equivalent alternative: a single **Owner** assignment at the same scope.

After this is done, **no further admin involvement is needed**. CI runs `terraform apply` unattended for every change.

## Service principal details

| Field | Value |
|---|---|
| Display name | `<fill in — the SPN backing GitHub Actions>` |
| Application (client) ID | `<value of GitHub secret AZURE_CLIENT_ID>` |
| Object ID (of the **service principal**, not the app reg) | `<look up in Entra ID → Enterprise applications>` |
| Tenant | Azure US Government |

> The Object ID is what `az role assignment create --assignee-object-id` needs.
> Get it with:
> ```bash
> az ad sp show --id <client-id> --query id -o tsv
> ```

## Scope

Preferred scope: **subscription**.
`/subscriptions/<sub-id>`

Tighter scope is possible but **not recommended for the first deploy**, because the Terraform also creates the resource groups themselves:

- `rg-tfstate-<env>` (state backend; created by `infra/bootstrap`)
- `rg-<env>` (workload primary)
- `rg-<env>-dr` (workload DR — only if `secondary_location` is set)

Scoping the SPN to those RGs requires you to **pre-create the RGs by hand** and grant the SPN rights on each individually. Subscription scope avoids that ceremony.

## Exact commands the admin runs (one-time, per environment subscription)

```bash
# Resolve the SPN Object ID once
SP_OID=$(az ad sp show --id <AZURE_CLIENT_ID> --query id -o tsv)
SUB=/subscriptions/<subscription-id>

# Option A — two narrow roles (recommended)
az role assignment create --assignee-object-id "$SP_OID" \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" --scope "$SUB"

az role assignment create --assignee-object-id "$SP_OID" \
  --assignee-principal-type ServicePrincipal \
  --role "User Access Administrator" --scope "$SUB"

# Option B — single broad role (functionally equivalent)
az role assignment create --assignee-object-id "$SP_OID" \
  --assignee-principal-type ServicePrincipal \
  --role "Owner" --scope "$SUB"
```

## What the Terraform does not need

To be explicit — **the deploying SPN does not need any of these**:

- ❌ Entra ID admin consent (no `azuread_*` resources, no Graph permissions)
- ❌ Global Admin, Privileged Role Administrator, or any Entra role
- ❌ Tenant-level role assignments
- ❌ Management-group-level role assignments
- ❌ Permission to create app registrations or service principals
- ❌ Permission to register Azure resource providers (the Gov subscription should already have these registered: `Microsoft.Storage`, `Microsoft.KeyVault`, `Microsoft.Web`, `Microsoft.Search`, `Microsoft.CognitiveServices`, `Microsoft.DocumentDB`, `Microsoft.Synapse`, `Microsoft.DataFactory`, `Microsoft.Network`, `Microsoft.OperationalInsights`, `Microsoft.Insights`, `Microsoft.ManagedIdentity`, `Microsoft.Cdn`)

If any of those RPs are not registered, the admin can pre-register them out of band:

```bash
az provider register --namespace Microsoft.CognitiveServices
# repeat for each
```

## Why User Access Administrator is needed

The Terraform creates user-assigned managed identities for the MCP server, the ingestion Functions, and Data Factory, then grants them the data-plane roles they need at runtime (e.g. `Storage Blob Data Contributor` on the workload storage account, `Search Index Data Contributor` on AI Search, `Cognitive Services OpenAI User` on the Foundry account). Each of those grants is a write to `Microsoft.Authorization/roleAssignments`, which **Contributor cannot perform**.

Full list of role assignments written by Terraform: `infra/modules/roleassignments/main.tf` (~18 assignments, all built-in roles, all scoped to resources within the workload subscription).

## Audit / revocation

- All assignments live in the subscription's activity log under `Microsoft.Authorization/roleAssignments/write`.
- The SPN's assignments can be enumerated with:
  ```bash
  az role assignment list --assignee <AZURE_CLIENT_ID> --all -o table
  ```
- Revocation: `az role assignment delete --assignee <AZURE_CLIENT_ID> --scope $SUB`. This blocks future deploys but does **not** revoke the workload identities Terraform has already created — those are independent and survive SPN revocation.

## After grant

Confirm with the platform team, then they can:

```bash
gh workflow run terraform-bootstrap.yml -f environment_name=dev -f location=usgovvirginia -f ci_principal_id=<SP_OID> -f azure_environment=usgovernment
gh workflow run terraform.yml -f environment=dev
```

No further admin involvement after that.

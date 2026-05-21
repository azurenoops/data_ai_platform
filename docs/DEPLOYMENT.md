# Deployment Guide — NSWC Port Hueneme Division

End-to-end, step-by-step procedure for deploying the Data + AI + MCP platform into NSWC PHD's **Flank Speed** (M365 GCC High) tenant and the matching **Azure Government** subscription.

This guide is intentionally exhaustive. Read it through once before running any commands — several steps require admin actions outside your control (Graph admin consent, Foundry quota, ATO sign-off) and the lead time on those will dictate your overall schedule.

---

> **⚠ Tooling notice — Terraform replaces Bicep + azd**
>
> The infrastructure was migrated from Bicep + Azure Developer CLI (`azd`) to **Terraform** (`infra/*.tf`, root composition + 15 modules under `infra/modules/`). The legacy `azd up` / `azd provision` flow no longer exists in this repository. Wherever this document still says "`azd provision`" or "`azd deploy`", read it as:
>
> | Old (`azd`) | New (Terraform + `az`) |
> | --- | --- |
> | `azd env new <name>` + `azd env set` | `terraform workspace new <env>` + edit [infra/envs/dev.tfvars](../infra/envs/dev.tfvars) / [infra/envs/prod.tfvars](../infra/envs/prod.tfvars) |
> | `azd provision` | One-time `cd infra/bootstrap && terraform init && terraform apply` (creates remote state SA), then `cd infra && terraform init -backend-config=…  && terraform apply -var-file=envs/<env>.tfvars` |
> | `azd deploy` | `dotnet publish` → upload ZIPs to the platform storage `deploy` container → set `WEBSITE_RUN_FROM_PACKAGE` URL on App Service and Function App. The CI workflow [.github/workflows/terraform.yml](../.github/workflows/terraform.yml) does this automatically after a successful Terraform apply. |
> | `terraform -chdir=infra output -json` | `terraform -chdir=infra output -json > tfout.json` |
> | `infra/main.bicep` + `infra/modules/*.bicep` | [infra/main.tf](../infra/main.tf), [infra/primary.tf](../infra/primary.tf), [infra/secondary.tf](../infra/secondary.tf), [infra/frontdoor.tf](../infra/frontdoor.tf), [infra/roles.tf](../infra/roles.tf), [infra/outputs.tf](../infra/outputs.tf), and `infra/modules/<name>/*.tf` |
> | `.github/workflows/terraform.yml` | Active workflow for terraform validate/plan/apply and application deployment. |
>
> **Required GitHub Actions configuration:**
>
> - **Secrets:** `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` (federated identity for OIDC login).
> - **Variables (Terraform backend):** `TFSTATE_RESOURCE_GROUP`, `TFSTATE_STORAGE_ACCOUNT`, `TFSTATE_CONTAINER` (output of the `infra/bootstrap/` run; see [infra/bootstrap/README.md](../infra/bootstrap/README.md)).
> - **Variables (tfvars content):** `TFVARS_DEV`, `TFVARS_PROD` — full text contents of `infra/envs/dev.tfvars` and `infra/envs/prod.tfvars` respectively. The tfvars files are gitignored (`.gitignore` line 37: `*.tfvars`), so CI reconstructs them from these variables. See [§15.4](#154-github-actions-repository-variables-tfvars-content).
> - **Environments:** `dev` and `prod` GitHub environments with required reviewers configured for the `apply` job approval gate.
>
> The body of this document still uses Azure-Government-specific guidance which is unchanged. Treat the `azd`/`bicep` commands below as historical context — the canonical workflow is the Terraform commands above and in [§8](#8-provision-infrastructure-azd-provision) / [§11](#11-deploy-application-code-azd-deploy) section bodies (now updated to Terraform).

---

## Table of contents

1. [Read this first](#1-read-this-first)
2. [Pre-flight checklist](#2-pre-flight-checklist)
3. [Decisions to lock in before you start](#3-decisions-to-lock-in-before-you-start)
4. [Workstation setup](#4-workstation-setup)
5. [Sovereign-cloud code adjustments](#5-sovereign-cloud-code-adjustments)
6. [Authenticate to Azure Government](#6-authenticate-to-azure-government)
7. [Create the Terraform workspace](#7-create-the-terraform-workspace)
8. [Provision infrastructure (`terraform apply`)](#8-provision-infrastructure-terraform-apply)
9. [Verify what was provisioned](#9-verify-what-was-provisioned)
10. [Manual post-provision configuration](#10-manual-post-provision-configuration)
11. [Deploy application code](#11-deploy-application-code)
12. [Smoke test the deployment](#12-smoke-test-the-deployment)
13. [Onboard data sources](#13-onboard-data-sources)
14. [Connect MCP clients](#14-connect-mcp-clients)
15. [CI/CD with GitHub Actions](#15-cicd-with-github-actions)
16. [Operations runbook](#16-operations-runbook)
17. [Troubleshooting](#17-troubleshooting)
18. [Rollback and tear-down](#18-rollback-and-tear-down)
19. [Appendix A — Required Azure RBAC roles](#appendix-a--required-azure-rbac-roles)
20. [Appendix B — Required Microsoft Graph permissions](#appendix-b--required-microsoft-graph-permissions)
21. [Appendix C — Sovereign-cloud endpoint reference](#appendix-c--sovereign-cloud-endpoint-reference)
22. [Appendix D — Pre-deploy checklist (signoff)](#appendix-d--pre-deploy-checklist-signoff)

---

## 1. Read this first

This deployment is **not** a "click `terraform apply` and wait" exercise in Azure Government. The current source tree was originally written against commercial Azure and Microsoft Graph commercial endpoints. Before the platform will function in Flank Speed / Azure Government you must:

- **Retarget hard-coded endpoints** from `*.com` to `*.us` in two places in the source tree (see [§5](#5-sovereign-cloud-code-adjustments)).
- **Verify Foundry model availability** in your chosen Gov region — the default Bicep targets `gpt-4o`, `gpt-4o-mini`, and `text-embedding-3-large` at specific versions which may not be GA in your region on the day you deploy (see [§3](#3-decisions-to-lock-in-before-you-start) and [infra/modules/foundry/main.tf](../infra/modules/foundry/main.tf)).
- **Get Microsoft Graph admin consent** for `Sites.Read.All` and `Files.Read.All` against your Flank Speed tenant. This requires a tenant-admin action you almost certainly cannot perform yourself; budget time for the request to clear DON CIO / Flank Speed support channels.
- **Have an authorized Azure Government subscription** federated with the Flank Speed Entra tenant. A commercial subscription cannot satisfy the IL4/IL5 boundary requirements.
- **Have ISSM/ISSO awareness and sign-off** on what data will be ingested. The single biggest risk in this pattern is over-collection — ingesting documents the consuming user population is not authorized to read.

Plan accordingly. The actual `azd` commands take well under an hour. Getting the surrounding approvals, consents, and quota in place can take days to weeks.

---

## 2. Pre-flight checklist

Before you run any command, confirm every item below. If something is missing, stop and resolve it — do not proceed assuming you can fix it later.

### Identity & access

- [ ] You can sign in to **Flank Speed** (M365 GCC High) with a valid CAC and your `.us` tenant credentials.
- [ ] You have a designated **Azure Government** subscription (not commercial). Subscription ID recorded.
- [ ] You hold (or have a sponsor who holds) **Owner** or **User Access Administrator + Contributor** at the subscription scope. The deployment creates RBAC role assignments, which require write access to `Microsoft.Authorization/roleAssignments`. Without this scope, `terraform apply` fails partway through [infra/modules/roleassignments/main.tf](../infra/modules/roleassignments/main.tf).
- [ ] You have the **Object ID (OID)** of your own Flank Speed user principal — used to grant dev data-plane access and Synapse SQL admin.

### Tenant administration (someone else, almost always)

- [ ] A Flank Speed **tenant administrator** is identified and engaged. They will need to admin-consent the Microsoft Graph application permissions ([Appendix B](#appendix-b--required-microsoft-graph-permissions)) once the user-assigned managed identity for the ingestion Function App is created.
- [ ] A path to register an **app registration** in Flank Speed Entra (for the MCP server's audience) has been agreed. Either the tenant admin will create it, or you have the standing delegation to do so.

### Azure region & quota

- [ ] An Azure Government **region** is chosen (typically `usgovvirginia` or `usgovarizona`). Recorded in pre-deploy notes.
- [ ] **Azure OpenAI / AI Foundry** is available in the chosen Gov region.
- [ ] Quota requests for the three model deployments have been submitted and **approved**:
  - `gpt-4o` (chat) — at least 30K TPM (matches `capacity: 30` in [infra/modules/foundry/main.tf](../infra/modules/foundry/main.tf)).
  - `gpt-4o-mini` (chat-mini) — at least 30K TPM.
  - `text-embedding-3-large` (embeddings) — at least 30K TPM.
- [ ] **AI Search**, **Document Intelligence**, **Synapse Workspace**, **Flex-Consumption Functions**, and **App Service Linux** are all available in the chosen region.

> **Note:** if any of those models or services are not GA in your Gov region, skip to [§3](#3-decisions-to-lock-in-before-you-start) and pick alternatives *before* starting the deployment. Re-embedding the corpus after the fact is expensive.

### Data classification & ingestion governance

- [ ] **In writing**, the data owners for every source library/site/table you plan to ingest have signed off. Start with a single pilot library; do not attempt a tenant-wide rollout in the first deploy.
- [ ] An **ISSM-acknowledged data-handling plan** exists: classification of ingested content (CUI / FOUO / unrestricted), retention, disposition on source-doc deletion, audit-log destination, and incident-response path for over-collection.
- [ ] Default position recorded: **OneDrive ingestion is OFF** unless a specific drive list is approved.

### Operational readiness

- [ ] An **App Insights / Log Analytics** workspace destination is agreed (the Bicep creates one in-region; if NSWC PHD has a central SIEM destination, plan diagnostic-setting forwarding before users arrive).
- [ ] A cost owner / cost center is recorded for the subscription.
- [ ] An on-call point of contact is identified for the platform once it goes live.

Sign the checklist in [Appendix D](#appendix-d--pre-deploy-checklist-signoff) before proceeding.

---

## 3. Decisions to lock in before you start

These are the parameters and configuration choices you will be asked for. Decide them once, write them down, and use them for every subsequent step.

| Decision | Where it's used | Default | Notes |
| --- | --- | --- | --- |
| **`environment_name` (tfvars)** | `terraform workspace new <env>` + `environment_name` in [infra/envs/<env>.tfvars](../infra/envs/) | — | Short, lowercase, no spaces. Becomes part of the resource group name `rg-<environment_name>` and is encoded into resource tags. Examples: `phd-dev`, `phd-pilot`, `phd-prod`. |
| **Azure Government region** | `AZURE_LOCATION` | — | `usgovvirginia` or `usgovarizona`. Verify all required services + models are GA. |
| **Subscription ID** | `AZURE_SUBSCRIPTION_ID` | — | Government subscription only. |
| **Foundry chat deployment** | `chatDeployment` parameter ([infra/main.tf](../infra/main.tf)) | `gpt-4o` | Override if `gpt-4o` is not available in your Gov region on the deploy date. |
| **Foundry chat-mini deployment** | `chatMiniDeployment` parameter | `gpt-4o-mini` | Same caveat. |
| **Foundry embedding deployment** | `embeddingDeployment` parameter | `text-embedding-3-large` | **Pick once and treat as versioned** — switching forces re-embedding the entire corpus. |
| **AI Search SKU** | `AZURE_SEARCH_SKU` | `standard` | `basic` works for a small POC; `standard2` / `standard3` for production at scale. |
| **App Service Plan SKU** | `AZURE_APP_SERVICE_PLAN_SKU` | `B1` | Step up to `P1v3` or higher for production load and to support VNet integration. |
| **CMK on/off** | `enableCmk` parameter | `false` | Decide before first deploy. Switching after the fact is non-trivial on AI Search. |
| **Multi-region DR** | `secondaryLocation` parameter | empty (off) | Only enable if the second region has the same model availability as the primary. |
| **Storage replication** | `storageSku` parameter | `Standard_LRS` | Auto-promoted to `Standard_RAGZRS` when DR is enabled. |
| **Auth audience** | `Auth__Audience` app setting | `api://<siteName>` | Decide whether to keep the auto-generated audience or front with a command-managed app registration exposing a named scope (e.g., `MCP.Read`). |
| **Reuse existing AI Search** | `use_existing_search` ([infra/variables.tf](../infra/variables.tf)) | `false` | Set `true` only when the Search service already exists in the target RG and Terraform should reference (not create) it. See [§7.4](#74-reuse-existing-resources-skip-create-toggles). |
| **Reuse existing Foundry account** | `use_existing_foundry_account` | `false` | Set `true` when an upstream platform team already owns the Foundry account. Model deployments and project connections must be managed out-of-band. See [§7.4](#74-reuse-existing-resources-skip-create-toggles). |
| **Reuse existing Data Factory** | `use_existing_data_factory` | `false` | Set `true` only when ADF pipelines/triggers/SHIR are managed elsewhere. Incompatible with `enable_data_factory_pipelines=true`. See [§7.4](#74-reuse-existing-resources-skip-create-toggles). |
| **Reuse existing Front Door** | `use_existing_front_door` | `false` | DR-only. Set `true` when an existing AFD profile + endpoint should be reused; origin group + route stay out-of-band. See [§7.4](#74-reuse-existing-resources-skip-create-toggles). |
| **Pilot SharePoint drive IDs** | `SharePoint__DriveIds` (Function App settings) | empty | Start narrow. Default empty until data owner sign-off is in writing. See [`docs/INGESTION.md`](INGESTION.md) for the full ingestion guide and [`docs/ingestion/sharepoint-files.md`](ingestion/sharepoint-files.md) for the drive-ID lookup procedure. |

Record all decisions in your pre-deploy notes alongside the [Appendix D](#appendix-d--pre-deploy-checklist-signoff) checklist.

---

## 4. Workstation setup

Use a workstation that is:

- Compliant with NSWC PHD / DON device policy for accessing Flank Speed.
- Allowed (by Conditional Access) to perform interactive sign-in to Azure Government.
- Able to reach `*.usgovcloudapi.net`, `login.microsoftonline.us`, and `graph.microsoft.us`.

Install:

| Tool | Minimum version | Verify |
| --- | --- | --- |
| .NET SDK | `9.0.100` (matches [global.json](../global.json)) | `dotnet --version` |
| Terraform | `1.9.0+` (CI uses `1.9.8`) | `terraform version` |
| Azure CLI (`az`) | `2.60+` | `az version` |
| `jq` | any modern version | required by [infra/scripts/postprovision.sh](../infra/scripts/postprovision.sh) and [infra/scripts/postdeploy.sh](../infra/scripts/postdeploy.sh) |
| Git | any modern version | `git --version` |
| `curl`, POSIX shell (`sh`/`zsh`/`bash`) | system default | hooks are sh scripts |
| *(Optional)* `tflint` | `v0.55+` | `tflint --version` (also enforced by CI) |
| *(Optional)* Azure Functions Core Tools v4 | latest v4 | `func --version` |
| *(Optional)* Azurite | latest | for local Functions dev |
| *(Optional)* `sqlcmd` | 18+ with AAD support | for pushing Synapse views |

### Clone and build

```bash
git clone <repo-url> data-ai-mcp
cd data-ai-mcp

# Restore + build + run unit tests as a pre-flight sanity check.
dotnet restore DataAiMcp.slnx
dotnet build   DataAiMcp.slnx -c Release
dotnet test    DataAiMcp.slnx -c Release --no-build
```

A green build before `terraform apply` saves a lot of round-trips — `postdeploy` also runs the smoke project against the deployed URL.

### Validate Terraform locally

```bash
cd infra
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate
```

If this fails, fix the Terraform before doing anything else. The CI workflow in [.github/workflows/ci.yml](../.github/workflows/ci.yml) does the same checks plus `tflint --recursive`.

---

## 5. Sovereign-cloud code adjustments

The current source assumes commercial Azure / commercial Microsoft Graph. **Before deploying to Flank Speed / Azure Government you must retarget the hard-coded endpoints below.** Symptoms when you forget: `AADSTS50020`, 401s, empty Graph result sets, "user account does not exist in tenant" errors.

### 5.1 MCP server: Entra authority

In [src/DataAiMcp.McpServer/Program.cs](../src/DataAiMcp.McpServer/Program.cs), the JWT Bearer authority is currently:

```csharp
options.Authority = $"https://login.microsoftonline.com/{authOptions.TenantId}/v2.0";
```

Change it to the Gov authority:

```csharp
options.Authority = $"https://login.microsoftonline.us/{authOptions.TenantId}/v2.0";
```

If you want to keep the code cloud-agnostic, externalize the authority host as a configuration value (e.g., `Auth:Authority`) and set it in app settings — `https://login.microsoftonline.us` for Gov, `https://login.microsoftonline.com` for commercial.

### 5.2 Ingestion Functions: Microsoft Graph base URL

In [src/DataAiMcp.Ingestion.Functions/Graph/GraphClientFactory.cs](../src/DataAiMcp.Ingestion.Functions/Graph/GraphClientFactory.cs), confirm the Graph client is created against `https://graph.microsoft.us`. If the factory currently relies on the SDK default (commercial), construct it with:

```csharp
var client = new GraphServiceClient(credential, scopes: new[] { "https://graph.microsoft.us/.default" })
{
    BaseUrl = "https://graph.microsoft.us/v1.0"
};
```

The credential must be a `DefaultAzureCredential` (or `ManagedIdentityCredential`) configured for the Azure Government cloud — see §5.3.

### 5.3 `DefaultAzureCredential` / `TokenCredential` — Azure Government authority

`Azure.Identity` defaults to the public cloud authority host. Set it explicitly:

```csharp
var credential = new DefaultAzureCredential(new DefaultAzureCredentialOptions
{
    AuthorityHost = AzureAuthorityHosts.AzureGovernment,
});
```

Apply this in any place a credential is constructed, including [src/DataAiMcp.Shared/Auth/AzureCredentialFactory.cs](../src/DataAiMcp.Shared/Auth/AzureCredentialFactory.cs) and [src/Samples/DataAiMcp.SampleClient.Console/Program.cs](../src/Samples/DataAiMcp.SampleClient.Console/Program.cs).

### 5.4 Application Insights (optional)

If you use a Gov-only App Insights connection string, no code change is needed — the Bicep already wires `APPLICATIONINSIGHTS_CONNECTION_STRING` from the deployed resource.

### 5.5 Verify before deploying

After making the changes above, rebuild and re-test:

```bash
dotnet build DataAiMcp.slnx -c Release
dotnet test  DataAiMcp.slnx -c Release --no-build
```

Commit the changes on a feature branch. Do not deploy with stale endpoints.

---

## 6. Authenticate to Azure Government

This is the step where most first-time Gov-cloud deployments go wrong. Follow it exactly.

### 6.1 Switch the Azure CLI to the Gov cloud

```bash
az cloud set --name AzureUSGovernment
az cloud show --query name -o tsv
# Expected: AzureUSGovernment
```

### 6.2 Sign out of any commercial credentials

```bash
az logout
```

This avoids the most common pitfall: deploying to a Gov subscription while still authenticated against commercial credentials cached from a previous session.

### 6.3 Sign in to the Gov tenant

```bash
az login --tenant <flank-speed-tenant-id> --use-device-code
# Open the printed URL on a Flank Speed-compliant browser session,
# enter the device code, and complete CAC sign-in.
```

### 6.4 Confirm tenant and subscription

```bash
az account show --query "{tenantId: tenantId, subscriptionId: id, name: name}"
```

The `tenantId` must match your Flank Speed tenant. The subscription must be the Azure Government subscription you recorded in [§2](#2-pre-flight-checklist). If either is wrong, **stop** and resolve it before proceeding.

### 6.5 Set the active subscription

```bash
az account set --subscription <subscription-id>
```

### 6.6 Capture your principal Object ID

```bash
az ad signed-in-user show --query id -o tsv
```

Record the output — `azd` will set it as `AZURE_PRINCIPAL_ID` automatically, but having it explicit makes troubleshooting easier.

---

## 7. Create the Terraform workspace

The Terraform configuration uses **workspaces** to isolate state per environment (`dev`, `prod`). Workspace state is kept in the remote Azure Storage backend created by `infra/bootstrap/`.

### 7.1 First-time only — bootstrap remote state

You have two ways to run the bootstrap. Both produce the same Azure resources and the same three outputs.

#### Option A — CI-driven (recommended for restricted environments / no local Azure CLI)

Use this when operators can't run `az login` and `terraform` from their workstation (e.g. NVD-isolated machines, locked-down Gov endpoints).

1. GitHub UI → **Actions** → **terraform-bootstrap** → **Run workflow**.
2. Pick `environment_name` (e.g. `shared`), `location`, optionally `ci_principal_id`, and `azure_environment` (`public` or `usgovernment`).
3. When the workflow finishes, copy the three values from the job summary into **Settings → Secrets and variables → Actions → Variables** as `TFSTATE_RESOURCE_GROUP`, `TFSTATE_STORAGE_ACCOUNT`, `TFSTATE_CONTAINER`.

The workflow uses OIDC federated identity (no client secrets), persists the bootstrap state in the GitHub Actions cache for fast re-runs, and self-heals via `terraform import` if the cache is evicted. Full design notes in [infra/bootstrap/README.md](../infra/bootstrap/README.md).

#### Option B — Local (operator workstation)

```bash
cd infra/bootstrap
terraform init
terraform apply
```

This creates the state resource group, ZRS storage account, and `tfstate` container in your subscription. Note its outputs (`tfstate_resource_group`, `tfstate_storage_account`, `tfstate_container`) — they feed every subsequent `terraform init -backend-config=...` and the GitHub Actions repo variables `TFSTATE_RESOURCE_GROUP`, `TFSTATE_STORAGE_ACCOUNT`, `TFSTATE_CONTAINER`. Read [infra/bootstrap/README.md](../infra/bootstrap/README.md) for full details. The bootstrap project is run **once per subscription** and uses local state — never check the resulting `terraform.tfstate` into git.

### 7.2 Init the main config and select a workspace

```bash
cd infra
terraform init \
  -backend-config="resource_group_name=<from-bootstrap>" \
  -backend-config="storage_account_name=<from-bootstrap>" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=data-ai-mcp.tfstate"

terraform workspace new dev      # or: terraform workspace select dev
```

### 7.3 Customize the tfvars file

Open [infra/envs/dev.tfvars](../infra/envs/dev.tfvars) (or `prod.tfvars`) and set the values you decided in [§3](#3-decisions-to-lock-in-before-you-start):

```hcl
environment_name      = "phd-pilot"
location              = "usgovvirginia"
search_sku            = "standard"
app_service_plan_sku  = "B1"
chat_deployment       = "gpt-4o"
chat_mini_deployment  = "gpt-4o-mini"
embedding_deployment  = "text-embedding-3-large"
enable_cmk            = false
secondary_location    = ""             # set to e.g. "usgovarizona" to enable DR
storage_sku           = "Standard_LRS"
front_door_sku        = "Standard_AzureFrontDoor"
# principal_id        = "<your-aad-objectId>"   # optional, for dev data-plane RBAC
```

The complete schema is in [infra/variables.tf](../infra/variables.tf).

> **`*.tfvars` is gitignored.** The file lives on your workstation only; CI reconstructs it from the `TFVARS_DEV` / `TFVARS_PROD` GitHub repo variables before running `terraform plan` (see [§15.4](#154-github-actions-repository-variables-tfvars-content)). Every change must be applied in **both** places — local file (for `terraform plan` from your workstation) and GitHub Variable (for CI). There is no automatic sync.

### 7.4 Reuse existing resources (skip-create toggles)

Some Azure resources may already exist in the target subscription because they were stood up by a prior deployment, a shared-platform team, or a Bicep run that predates the Terraform migration. The toggles below let Terraform **reference** an existing resource via a `data` source instead of trying to **create** it. RBAC, app settings, alerts, and outputs are still wired against the referenced resource ID, so the rest of the stack continues to work unchanged.

Each toggle defaults to `false` (create from scratch). Flip to `true` only when the matching Azure resource is already present and you want Terraform to leave its lifecycle alone.

| Variable | Default | What it does | Required companion variables |
| --- | --- | --- | --- |
| `use_existing_search` | `false` | Skips creating the AI Search service. Reads the existing service via `data.azurerm_search_service.existing` and uses its name + endpoint downstream. | `existing_search_name` (defaults to `local.names.search`), `existing_search_resource_group_name` (defaults to the primary RG). |
| `use_existing_foundry_account` | `false` | Skips creating the Foundry (Cognitive Services AIServices) account **and** its project, model deployments, and project connections. Reads the existing account via `data.azurerm_cognitive_account.existing_foundry`. | `existing_foundry_account_name`, `existing_foundry_account_resource_group_name`, `existing_foundry_project_name`. |
| `use_existing_data_factory` | `false` | Skips creating the Data Factory **and every child resource defined inside the module** (linked services, datasets, pipelines, triggers, SHIR). Reads the existing factory via `data.azurerm_data_factory.existing`. | `existing_data_factory_name`, `existing_data_factory_resource_group_name`. Incompatible with `enable_data_factory_pipelines=true`, `enable_self_hosted_integration_runtime=true`, and `enable_shir_host_vm=true` — plan-time precondition will fail. |
| `use_existing_front_door` | `false` | (DR only — no-op when `secondary_location=""`). Skips creating the Front Door profile, endpoint, origin group, origins, and route. Reads the existing profile + endpoint via `data.azurerm_cdn_frontdoor_profile.existing` / `data.azurerm_cdn_frontdoor_endpoint.existing`. | `existing_front_door_profile_name`, `existing_front_door_endpoint_name` (defaults to `{profile}-ep`), `existing_front_door_resource_group_name`. |

> **All `existing_*_name` variables default to `null` and fall back to the same `local.names.*` value Terraform would have generated for a fresh deploy.** That means a previously-Terraform-created resource can be "adopted" simply by flipping the toggle — no name lookup needed. Override the name explicitly when the existing resource was created with a different name (e.g. shared-platform Foundry account named `cs-foundry-shared`).

#### What changes when you flip a toggle

Flipping a toggle from `false` → `true` on an existing workspace produces a **destroy/import boundary**. Read this carefully before running `terraform apply`:

1. **Terraform will plan a `destroy` for the module's resources.** That is wrong — the resources still exist in Azure, they're just no longer managed. **Do not apply this plan.** Instead:
   ```bash
   # For module.search:
   terraform state list | grep '^module\.search\['
   # Remove the module and every child resource from state (without touching Azure):
   terraform state rm 'module.search[0]'
   # …repeat for module.foundry[0], module.datafactory[0], module.frontdoor[0] as needed.
   ```
2. After `terraform state rm`, re-run `terraform plan`. The plan should now show only the new `data` source reads and an in-place re-assignment of role assignments (scope ID resolves to the same Azure resource, so RBAC is re-applied but not lost).
3. Apply.

Flipping a toggle from `true` → `false` is the inverse: Terraform will try to **create** a resource that already exists in Azure and fail with a 409 Conflict. To switch back to managed:
1. Set the toggle to `false` and run `terraform plan` to see the create operations.
2. Import each resource into state with `terraform import module.<name>[0].<resource> <azure-resource-id>` (see provider docs for the exact resource address).
3. Re-run plan — should show no changes (or only drift on attributes the original creator set differently).

#### Caveats per toggle

- **`use_existing_search`** — If `enable_cmk=true`, the existing Search service must already be configured with `encryptionWithCmk.enforcement = Enabled`. The data source only reads; it cannot enforce CMK on a service that was created without it. The Search service's SystemAssigned identity is required for the CMK Key Vault role assignment — if the existing service was created without it, the CMK key-access role grant is silently skipped (the `compact()` filter in [infra/roles.tf](../infra/roles.tf) drops empty principal IDs). Re-create the service with SystemAssigned identity before flipping `enable_cmk=true`.
- **`use_existing_foundry_account`** — Model deployments (`chat_deployment`, `chat_mini_deployment`, `embedding_deployment`) and the `aisearch` + `datalake` project connections are **not** re-created on the referenced account. The MCP server and ingestion Function App expect those deployment names to resolve to live deployments — create them out-of-band before deploying app code, or the first chat / embedding call will 404. `existing_foundry_project_name` is used only to build the `Foundry__ProjectEndpoint` URL; it does not need to be a project that Terraform owns.
- **`use_existing_data_factory`** — Setting this to `true` skips **every** resource inside [infra/modules/datafactory/](../infra/modules/datafactory/): all linked services (`ls_adls`, `ls_kv`, `ls_sqlmi`, `ls_afs`, `ls_sharepoint`), datasets, pipelines (`pl_sql_mi_to_adls`, `pl_afs_to_adls`, `pl_sharepoint_lists_to_adls`, `pl_dataverse_marker`), schedule triggers, and the Self-Hosted Integration Runtime. The platform_ops alerts (failure rate, pipeline outcomes) still bind to the referenced factory ID and will fire on pipelines you create out-of-band. If you need Terraform to manage child resources against an existing factory, that's a deeper refactor of the `datafactory` module (take an `existing_factory_id` input instead of creating `azurerm_data_factory.this`); not in scope for this toggle.
- **`use_existing_front_door`** — Only takes effect when DR is enabled (`secondary_location != ""`). The origin group, origins (primary + secondary), and route are **not** re-created on the referenced profile. You must manage them out-of-band so the AFD endpoint actually forwards to the App Services. The `FRONT_DOOR_ID` output uses the referenced profile's `resource_guid` for the FDID app-setting binding — if the existing profile is shared across multiple workloads, every workload behind it will see the same FDID header.

#### When NOT to use these toggles

These toggles are an escape hatch for "the resource already exists and I cannot delete it". They are **not** a refactoring shortcut. Prefer the standard create path when:

- You are deploying to a fresh subscription / resource group with no prior state.
- The resource was created by a previous `terraform apply` from this repository — that's the canonical state and Terraform should keep owning it.
- You want CMK enforcement, model deployment management, or pipeline definitions to be Terraform-managed (toggles bypass all of these).

Record any reuse decision in your pre-deploy notes alongside the [Appendix D](#appendix-d--pre-deploy-checklist-signoff) checklist, including the owner of the referenced resource and the runbook for managing its lifecycle out-of-band.

---

## 8. Provision infrastructure (`terraform apply`)

```bash
cd infra
terraform plan  -var-file=envs/dev.tfvars -out=tfplan
terraform apply tfplan
```

This submits a subscription-scoped deployment to Azure Government, creating resource group `rg-<environment_name>` with everything in [What gets deployed](README.md#what-gets-deployed).

### What you should see

1. `terraform plan` shows ~80 resources to create (varies based on `enable_cmk` and `secondary_location`). Review the diff carefully.
2. `terraform apply` progresses through the modules. The Foundry model deployments are created **sequentially** (chained `depends_on` to mirror the original Bicep `@batchSize(1)`) — this is the slowest step and is where region/model availability errors surface.
3. On success, capture the outputs for downstream scripts:

   ```bash
   terraform output -json > tfout.json
   TFOUT_JSON=$(pwd)/tfout.json ./scripts/postprovision.sh
   ```

   The post-provision script runs [src/DataAiMcp.Tools.IndexProvisioner](../src/DataAiMcp.Tools.IndexProvisioner/) to create the AI Search `documents` index, and stages Synapse view DDL with the deployed storage account name (the actual `sqlcmd` push is left commented out — see [§10.3](#103-push-synapse-views)).

### If it fails

Common provision-time failures and their resolutions are in [§17 Troubleshooting](#17-troubleshooting). Do not retry blindly — read the error first. Most failures are quota or RBAC related and require a config change before retry.

After fixing the underlying issue, re-run `terraform apply`. Terraform is idempotent; existing resources are reconciled, not recreated.

---

## 9. Verify what was provisioned

After `terraform apply` completes, verify the deployment is structurally sound before you put any data into it.

### 9.1 List outputs

```bash
cd infra
terraform output -json | jq '. | with_entries(.value = .value.value) | to_entries[] | select(.key | test("STORAGE_|SEARCH_|FOUNDRY_|SYNAPSE_|APP_SERVICE_|FUNCTION_|MCP_SERVER_"))'
```

Expected outputs include:

- `MCP_SERVER_BASE_URL` — full HTTPS URL of the App Service (or Front Door endpoint when DR enabled).
- `APP_SERVICE_NAME`, `APP_SERVICE_HOSTNAME`
- `FUNCTION_APP_NAME`
- `STORAGE_ACCOUNT_NAME`, `STORAGE_BLOB_ENDPOINT`, `STORAGE_DFS_ENDPOINT`
- `SEARCH_ENDPOINT`, `SEARCH_NAME`, `SEARCH_INDEX_NAME=documents`
- `FOUNDRY_ACCOUNT_ENDPOINT`, `FOUNDRY_PROJECT_ENDPOINT`, `FOUNDRY_CHAT_DEPLOYMENT`, `FOUNDRY_EMBEDDING_DEPLOYMENT`
- `DOCUMENT_INTELLIGENCE_ENDPOINT`
- `SYNAPSE_SERVERLESS_SQL_ENDPOINT`, `SYNAPSE_WORKSPACE_NAME`
- `MCP_SERVER_IDENTITY_CLIENT_ID`, `INGESTION_IDENTITY_CLIENT_ID`

### 9.2 Verify Foundry deployments

```bash
RG="$(terraform -chdir=infra output -raw AZURE_RESOURCE_GROUP)"
FOUNDRY_HOST="$(terraform -chdir=infra output -raw FOUNDRY_ACCOUNT_ENDPOINT | sed -E 's|https://([^.]+).*|\1|')"

az cognitiveservices account deployment list \
  --resource-group "$RG" \
  --name "$FOUNDRY_HOST" \
  --output table
```

Confirm the three deployments (`chat_deployment`, `chat_mini_deployment`, `embedding_deployment`) are `Succeeded` and their model names match your decisions in [§3](#3-decisions-to-lock-in-before-you-start).

### 9.3 Verify the AI Search index

The post-provision hook should have created the `documents` index. Confirm:

```bash
az search service show \
  --name "$(terraform -chdir=infra output -raw SEARCH_NAME)" \
  --resource-group "$(terraform -chdir=infra output -raw AZURE_RESOURCE_GROUP)" \
  --query "name"

# Or check the index directly via REST (data-plane requires AAD token):
curl -H "Authorization: Bearer $(az account get-access-token --resource https://search.azure.us --query accessToken -o tsv)" \
  "$(terraform -chdir=infra output -raw SEARCH_ENDPOINT)/indexes?api-version=2024-07-01" | jq '.value[].name'
```

You should see `documents` in the list. If not, re-run the provisioner manually:

```bash
eval "$(terraform -chdir=infra output -json | jq -r 'to_entries[] | "export " + .key + "=" + (.value.value | @sh)')"
dotnet run --project src/DataAiMcp.Tools.IndexProvisioner
```

### 9.4 Verify role assignments

```bash
az role assignment list \
  --assignee "$(terraform -chdir=infra output -raw MCP_SERVER_IDENTITY_CLIENT_ID)" \
  --all -o table

az role assignment list \
  --assignee "$(terraform -chdir=infra output -raw INGESTION_IDENTITY_CLIENT_ID)" \
  --all -o table
```

Confirm each identity has the roles listed in [Appendix A](#appendix-a--required-azure-rbac-roles). RBAC propagation can take a few minutes — if assignments look incomplete, wait and re-check.

### 9.5 Verify the App Service is healthy at the platform level

```bash
az webapp show \
  --name "$(terraform -chdir=infra output -raw APP_SERVICE_NAME)" \
  --resource-group "$(terraform -chdir=infra output -raw AZURE_RESOURCE_GROUP)" \
  --query "{state: state, hostName: defaultHostName}"
```

State must be `Running`. The application itself is not deployed yet — that happens in [§11](#11-deploy-application-code-azd-deploy).

---

## 10. Manual post-provision configuration

Some configuration is intentionally left for the operator because it requires tenant-admin actions, data-owner sign-off, or sensitive credentials.

### 10.1 Get Microsoft Graph admin consent

The Function App's user-assigned managed identity needs the application permissions in [Appendix B](#appendix-b--required-microsoft-graph-permissions) on Microsoft Graph. **A Flank Speed tenant admin must consent.**

Steps the tenant admin will follow:

1. In Azure Government Portal → **Microsoft Entra ID** → **Enterprise applications**, find the managed identity by `INGESTION_IDENTITY_CLIENT_ID`.
2. **Permissions** → **Grant admin consent** for `Sites.Read.All` and `Files.Read.All` (Application permissions).
3. Optionally narrow with [resource-specific consent](https://learn.microsoft.com/graph/auth-limit-mailbox-access) so the identity can only read the specific sites you intend to ingest.

You can also script the request using the Microsoft Graph PowerShell SDK if your tenant admin prefers a scripted artifact for change-management.

Until consent is granted, the SharePoint and OneDrive ingestion functions will fail at runtime with `403 Forbidden`.

### 10.2 Wire Data Factory linked services

The pipelines in [infra/datafactory/pipelines](../infra/datafactory/pipelines) reference SQL MI, Dataverse Synapse Link, and Azure Files. The pipeline JSON is deployed by the Bicep but the **linked services** are not — they require source-system credentials and network reachability that vary per environment.

For each pipeline:

1. Open the deployed Data Factory in the Azure Government Portal → **Author** → **Linked services**.
2. Create the linked service with the Data Factory's user-assigned managed identity (`MCP_SERVER_IDENTITY_CLIENT_ID` and friends listed in `terraform -chdir=infra output -json`) — never with shared credentials.
3. Test the connection. If the source is on-prem or on a private network, deploy a **self-hosted integration runtime** in the appropriate enclave and bind the linked service to it.
4. Re-validate the pipeline.

### 10.3 Push Synapse views

The post-provision hook stages the SQL but does not push it (the `sqlcmd` line is commented). To push manually:

```bash
eval "$(terraform -chdir=infra output -json | jq -r 'to_entries[] | "export " + .key + "=" + (.value.value | @sh)')"

for sql in infra/synapse/views/*.sql; do
  sed "s/__STORAGE_ACCOUNT__/${STORAGE_ACCOUNT_NAME}/g" "$sql" > "${sql}.tmp"
  sqlcmd -S "${SYNAPSE_SERVERLESS_SQL_ENDPOINT}" -G -d master -i "${sql}.tmp"
  rm -f "${sql}.tmp"
done
```

`sqlcmd -G` uses Entra authentication — your signed-in principal must be the Synapse SQL admin (set by `principalId` during provision).

You can alternatively open Synapse Studio and run each `.sql` file via the Develop hub.

### 10.4 Configure ingestion app settings

Set the Function App settings the Bicep cannot fill in for you (data-owner-specific values):

```bash
RG="$(terraform -chdir=infra output -raw AZURE_RESOURCE_GROUP)"
FUNC="$(terraform -chdir=infra output -raw FUNCTION_APP_NAME)"
TENANT="$(terraform -chdir=infra output -raw AZURE_TENANT_ID)"

az functionapp config appsettings set -n "$FUNC" -g "$RG" --settings \
  Graph__TenantId="$TENANT" \
  SharePoint__DriveIds="<approved-drive-ids,comma-separated>" \
  OneDrive__DriveIds=""    # default OFF
```

Restart the Function App after changing settings:

```bash
az functionapp restart -n "$FUNC" -g "$RG"
```

### 10.5 (Optional) Front the MCP server with a custom app registration

If you decided to expose a named scope (e.g., `MCP.Read`) instead of the default `api://<siteName>` audience, your tenant admin should:

1. Create an **app registration** in Flank Speed Entra.
2. Set Application ID URI to `api://mcp-phd-<env>` (or your standard).
3. Expose a scope `MCP.Read` (and optionally `MCP.Admin`).
4. Add the **App role** `DataAiMcp.Admin` (used by [src/DataAiMcp.McpServer/Program.cs](../src/DataAiMcp.McpServer/Program.cs) for the `AdminTools` policy).
5. Assign user/group membership through Conditional Access.

Then update the App Service settings:

```bash
APP="$(terraform -chdir=infra output -raw APP_SERVICE_NAME)"
az webapp config appsettings set -n "$APP" -g "$RG" --settings \
  Auth__Audience="api://mcp-phd-<env>" \
  Auth__TenantId="$TENANT"
```

---

## 11. Deploy application code

There is no `azd deploy` step. Application code is deployed with `dotnet publish`, blob upload to the platform storage `deploy` container, and `WEBSITE_RUN_FROM_PACKAGE` app-setting updates (no Kudu dependency). The CI workflow [.github/workflows/terraform.yml](../.github/workflows/terraform.yml) does this automatically after apply; the manual procedure is below for local / break-glass use.

### 11.1 Build and upload packages

```bash
cd "$(git rev-parse --show-toplevel)"
RG="$(terraform -chdir=infra output -raw AZURE_RESOURCE_GROUP)"
APP="$(terraform -chdir=infra output -raw APP_SERVICE_NAME)"
FN="$(terraform -chdir=infra output -raw FUNCTION_APP_NAME)"
STORAGE_ACCOUNT="$(terraform -chdir=infra output -raw STORAGE_ACCOUNT_NAME)"
STORAGE_BLOB_ENDPOINT="$(terraform -chdir=infra output -raw STORAGE_BLOB_ENDPOINT)"

dotnet publish src/DataAiMcp.McpServer/DataAiMcp.McpServer.csproj \
  --configuration Release \
  --output publish/mcp-server \
  /p:UseAppHost=false
(cd publish/mcp-server && zip -qr ../mcp-server.zip .)

dotnet publish src/DataAiMcp.Ingestion.Functions/DataAiMcp.Ingestion.Functions.csproj \
  --configuration Release \
  --output publish/functions \
  /p:UseAppHost=false
(cd publish/functions && zip -qr ../functions.zip .)

EXPIRY_UTC="$(date -u -d '+30 days' '+%Y-%m-%dT%H:%MZ')"
MCP_BLOB_NAME="mcp-server-$(date -u +%Y%m%d%H%M%S).zip"
FUNC_BLOB_NAME="functions-$(date -u +%Y%m%d%H%M%S).zip"

MCP_UPLOAD_SAS="$(az storage blob generate-sas \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name deploy \
  --name "$MCP_BLOB_NAME" \
  --permissions acw \
  --expiry "$EXPIRY_UTC" \
  --https-only \
  --as-user \
  --auth-mode login -o tsv)"

FUNC_UPLOAD_SAS="$(az storage blob generate-sas \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name deploy \
  --name "$FUNC_BLOB_NAME" \
  --permissions acw \
  --expiry "$EXPIRY_UTC" \
  --https-only \
  --as-user \
  --auth-mode login -o tsv)"

az storage blob upload \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name deploy \
  --name "$MCP_BLOB_NAME" \
  --file publish/mcp-server.zip \
  --sas-token "$MCP_UPLOAD_SAS" \
  --overwrite true

az storage blob upload \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name deploy \
  --name "$FUNC_BLOB_NAME" \
  --file publish/functions.zip \
  --sas-token "$FUNC_UPLOAD_SAS" \
  --overwrite true

MCP_READ_SAS="$(az storage blob generate-sas \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name deploy \
  --name "$MCP_BLOB_NAME" \
  --permissions r \
  --expiry "$EXPIRY_UTC" \
  --https-only \
  --as-user \
  --auth-mode login -o tsv)"

FUNC_READ_SAS="$(az storage blob generate-sas \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name deploy \
  --name "$FUNC_BLOB_NAME" \
  --permissions r \
  --expiry "$EXPIRY_UTC" \
  --https-only \
  --as-user \
  --auth-mode login -o tsv)"

MCP_PACKAGE_URL="${STORAGE_BLOB_ENDPOINT}deploy/${MCP_BLOB_NAME}?${MCP_READ_SAS}"
FUNC_PACKAGE_URL="${STORAGE_BLOB_ENDPOINT}deploy/${FUNC_BLOB_NAME}?${FUNC_READ_SAS}"
```

### 11.2 Configure run-from-package URLs

```bash
az webapp config appsettings set \
  --resource-group "$RG" \
  --name "$APP" \
  --settings WEBSITE_RUN_FROM_PACKAGE="$MCP_PACKAGE_URL"

az functionapp config appsettings set \
  --resource-group "$RG" \
  --name "$FN" \
  --settings WEBSITE_RUN_FROM_PACKAGE="$FUNC_PACKAGE_URL"

az webapp restart --resource-group "$RG" --name "$APP"
az functionapp restart --resource-group "$RG" --name "$FN"
```

### 11.3 Ingestion Functions (notes)

Kudu zip deploy (`az functionapp deployment source config-zip`) is intentionally not used because both apps run with public network access disabled.

Cold-start latency on the first request is normal; subsequent requests warm up.

### 11.4 Run the post-deploy smoke

```bash
terraform -chdir=infra output -json > infra/tfout.json
TFOUT_JSON=$(pwd)/infra/tfout.json ./infra/scripts/postdeploy.sh
```

This hits `/healthz` on the deployed URL and runs `tests/DataAiMcp.Smoke.Tests` against the deployed `MCP_SERVER_BASE_URL`. A non-zero exit indicates the smoke project failed; review the test output before declaring victory.

---

## 12. Smoke test the deployment

### 12.1 Anonymous health endpoint

```bash
curl "$(terraform -chdir=infra output -raw MCP_SERVER_BASE_URL)/healthz"
# {"status":"ok"}
```

If this fails:
- Confirm the App Service is `Running` (`az webapp show ...`).
- Tail App Service logs (`az webapp log tail`) to see startup errors.

### 12.2 Authenticated MCP tool call

```bash
APP_NAME="$(terraform -chdir=infra output -raw APP_SERVICE_NAME)"

# Acquire a token for the audience the App Service is configured for.
TOKEN="$(az account get-access-token --resource "api://${APP_NAME}" --query accessToken -o tsv)"

curl -s "$(terraform -chdir=infra output -raw MCP_SERVER_BASE_URL)/mcp/tools" \
  -H "Authorization: Bearer ${TOKEN}" | jq
```

A 200 with a list of tools indicates auth and routing work. A 401 means token audience or authority mismatch — re-read [§5.1](#51-mcp-server-entra-authority) and [§10.5](#105-optional-front-the-mcp-server-with-a-custom-app-registration).

### 12.3 Sample client end-to-end

```bash
dotnet run --project src/Samples/DataAiMcp.SampleClient.Console -- \
  "$(terraform -chdir=infra output -raw MCP_SERVER_BASE_URL)" \
  "api://$(terraform -chdir=infra output -raw APP_SERVICE_NAME)"
```

Expected output: a list of registered tools, then output from `list_sources` and `search_documents`. The latter returns zero hits until you ingest data — that's expected for a fresh deployment.

### 12.4 Run the smoke test project explicitly

```bash
terraform -chdir=infra output -json > infra/tfout.json
export TFOUT_JSON=$(pwd)/infra/tfout.json
export MCP_SERVER_BASE_URL=$(jq -r '.MCP_SERVER_BASE_URL.value' "$TFOUT_JSON")
dotnet test tests/DataAiMcp.Smoke.Tests/DataAiMcp.Smoke.Tests.csproj -c Release
```

---

## 13. Onboard data sources

Detailed per-source onboarding lives in the **[Ingestion guide](INGESTION.md)** — that hub plus its per-source cookbooks under [`docs/ingestion/`](ingestion/) is the single source of truth for connector configuration. Always start with one approved pilot source and expand only after the pilot is observably working.

Quick links by source type:

- [SharePoint files](ingestion/sharepoint-files.md) (Graph drives → `landing/`)
- [OneDrive files](ingestion/onedrive-files.md) (per-user, opt-in)
- [Azure File Share](ingestion/azure-file-share.md) (ADF + KV-stored key)
- [SQL Managed Instance](ingestion/sql-managed-instance.md) (ADF + MI auth)
- [SharePoint Lists](ingestion/sharepoint-lists.md) (ADF + AAD app-reg)
- [Dataverse](ingestion/dataverse.md) (Synapse Link)
- [Manual blob drop](ingestion/blob-drop.md) (ad-hoc upload)

For Graph admin-consent (`Sites.Read.All` + `Files.Read.All`), see [Appendix B](#appendix-b--required-microsoft-graph-permissions) below — the consent procedure is environment-specific and remains documented inline.

For the structured-data ACL trade-off that applies to SQL MI / SharePoint Lists / Dataverse, see [`docs/INGESTION.md`](INGESTION.md#51-why-structured-queries-dont-enforce-securityids).

---

## 14. Connect MCP clients

### 14.1 VS Code (`.vscode/mcp.json`)

```jsonc
{
  "servers": {
    "data-ai-mcp": {
      "type": "http",
      "url": "https://<APP_SERVICE_HOSTNAME>/mcp",
      "headers": {
        "Authorization": "Bearer ${input:bearerToken}"
      }
    }
  },
  "inputs": [
    { "type": "promptString", "id": "bearerToken", "password": true }
  ]
}
```

Get a bearer token for testing:

```bash
az account get-access-token \
  --resource "api://$(terraform -chdir=infra output -raw APP_SERVICE_NAME)" \
  --query accessToken -o tsv
```

### 14.2 Sample console client

See [§12.3](#123-sample-client-end-to-end). Use this as the reference for any custom client your team builds.

### 14.3 Other clients

- **GitHub Copilot Enterprise** — confirm the Gov-cloud endpoint is reachable from the Copilot agent before depending on it.
- **Microsoft 365 Copilot agents** — availability in Flank Speed varies; check current Microsoft 365 GCC High roadmap before committing.
- **Custom bots** — use the official MCP C# / TypeScript / Python SDKs. Configure the credential for `AzureAuthorityHosts.AzureGovernment`.

---

## 15. CI/CD with GitHub Actions

The repo ships two Terraform-aware workflows: [`ci.yml`](../.github/workflows/ci.yml) (build, test, terraform fmt/validate, tflint) and [`terraform.yml`](../.github/workflows/terraform.yml) (plan on PR, apply on main with environment approval, then app deployment via run-from-package URL). To use them with Azure Government:

### 15.1 Federated credential

In the **Flank Speed Entra tenant**, register an app registration for GitHub Actions OIDC and add a federated credential per environment with subject:

```
repo:<org>/<repo>:environment:<env-name>
```

For each environment you target (`dev`, `prod`). `terraform.yml` gates apply and deploy on the corresponding GitHub `environment:` so reviewers can require approvals before changes hit Azure.

### 15.2 GitHub Actions secrets

Set these at the repository level (or per environment):

| Secret | Value |
| --- | --- |
| `AZURE_CLIENT_ID` | App registration's client ID. |
| `AZURE_TENANT_ID` | Flank Speed tenant ID. |
| `AZURE_SUBSCRIPTION_ID` | Azure Government subscription ID. |

### 15.3 GitHub Actions repository variables (Terraform backend)

The Terraform workflows pull the remote-state location from **repository variables** (Settings → Secrets and variables → Actions → Variables), populated from the outputs of `infra/bootstrap/`:

| Variable | Value (from bootstrap output) |
| --- | --- |
| `TFSTATE_RESOURCE_GROUP` | `tfstate_resource_group` |
| `TFSTATE_STORAGE_ACCOUNT` | `tfstate_storage_account` |
| `TFSTATE_CONTAINER` | `tfstate_container` (typically `tfstate`) |

### 15.4 GitHub Actions repository variables (tfvars content)

`infra/envs/<env>.tfvars` files are **gitignored** (see [.gitignore](../.gitignore) line 37: `*.tfvars`). CI cannot read a file that isn't in the repo, so the workflows reconstruct each tfvars file from a repo-scoped GitHub Variable before running `terraform plan` / `terraform destroy`:

| Variable | Value |
| --- | --- |
| `TFVARS_DEV` | Full contents of [infra/envs/dev.tfvars](../infra/envs/dev.tfvars) (paste as plain text). |
| `TFVARS_PROD` | Full contents of [infra/envs/prod.tfvars](../infra/envs/prod.tfvars) (paste as plain text). |

The "Write tfvars from GitHub Variables" step in [.github/workflows/terraform.yml](../.github/workflows/terraform.yml) and [.github/workflows/terraform-destroy.yml](../.github/workflows/terraform-destroy.yml) writes the variable content to `infra/envs/${WORKSPACE}.tfvars` and registers it as a log mask so any value the operator considers sensitive does not leak into the workflow log. The workflow fails fast with a clear error if the variable is empty.

**How to update tfvars:**

1. Edit the file locally (`infra/envs/dev.tfvars` or `prod.tfvars`).
2. Validate locally: `cd infra && terraform plan -var-file=envs/dev.tfvars` (uses your local backend init).
3. Copy the entire file contents into the GitHub repo variable of the same name (Settings → Secrets and variables → Actions → Variables → `TFVARS_DEV` or `TFVARS_PROD` → "Update").
4. Trigger the `terraform` workflow (push to a branch + open PR for the plan, or `workflow_dispatch` for an out-of-cycle run).

> The local tfvars file and the GitHub Variable are **two copies of the same data** — there is no automatic sync. If you change one and forget the other, CI will plan against stale inputs and local runs will diverge from CI. A short pre-deploy checklist habit is the cheapest mitigation; a `pre-commit` hook that fails when the file is staged-but-not-pushed-to-vars is the next step if mismatches become a recurring issue.

> The variable content is read by CI but **never written back into the repo** — the destroy workflow uses the same mechanism so destroy-on-stale-state cannot happen. If the variable is unset, both workflows hard-fail before any Azure call.

If you treat any value in tfvars as sensitive (e.g. an `alert_webhook_url`), store it as a **GitHub Secret** instead and reference it as `${{ secrets.TFVARS_DEV }}` in the workflow `env:` block. The current implementation pulls from `vars.*` because the canonical tfvars contents (env name, SKUs, region, deployment names) are non-sensitive; flip to `secrets.*` if your threat model differs.

### 15.5 Patch the workflows for Gov cloud

The current workflows target the public cloud. For Azure Government, add the cloud parameter to the `azure/login@v2` steps and to the `azurerm` provider block:

```yaml
# .github/workflows/terraform.yml — every azure/login step
- name: Azure login (OIDC)
  uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
    environment: AzureUSGovernment   # <-- required for Gov
```

```hcl
# infra/main.tf — provider block
provider "azurerm" {
  features {}
  storage_use_azuread = true
  environment         = "usgovernment"   # <-- required for Gov
}
```

The Terraform azurerm backend also needs the `environment` argument when state lives in Azure Government — set it via `-backend-config="environment=usgovernment"` in both `terraform.yml` and `terraform-destroy.yml`.

Without these, the workflows will silently target commercial Azure even though the secrets point at Gov.

---

## 16. Operations runbook

### 16.1 Logs

```bash
RG="$(terraform -chdir=infra output -raw AZURE_RESOURCE_GROUP)"
APP="$(terraform -chdir=infra output -raw APP_SERVICE_NAME)"
FUNC="$(terraform -chdir=infra output -raw FUNCTION_APP_NAME)"

# Live tail
az webapp log tail -n "$APP" -g "$RG"
az functionapp log tail -n "$FUNC" -g "$RG"
```

App Insights / Log Analytics is wired automatically. Use Kusto in the Log Analytics workspace for correlation across services.

### 16.2 Cost & token telemetry

App Insights captures HTTP metrics but **not Foundry token spend by default**. Enable diagnostic settings on the Foundry account:

```bash
az monitor diagnostic-settings create \
  --name foundry-to-la \
  --resource "$(terraform -chdir=infra output -raw FOUNDRY_ACCOUNT_ENDPOINT | sed -E 's|https://([^/]+).*|\1|')" \
  --resource-type Microsoft.CognitiveServices/accounts \
  --workspace "$(terraform -chdir=infra output -raw LOG_ANALYTICS_WORKSPACE_ID)" \
  --logs '[{"category":"Audit","enabled":true},{"category":"RequestResponse","enabled":true}]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]'
```

Set a **cost alert** on the Foundry account. `query_structured_data` token usage scales with question complexity, not user count — a few power users can run up significant token spend.

### 16.3 Re-running the index provisioner

```bash
eval "$(terraform -chdir=infra output -json | jq -r 'to_entries[] | "export " + .key + "=" + (.value.value | @sh)')"
dotnet run --project src/DataAiMcp.Tools.IndexProvisioner
```

Idempotent. Run after schema changes in [src/DataAiMcp.Shared/Search](../src/DataAiMcp.Shared/Search).

### 16.4 Re-running post-provision

```bash
TFOUT_JSON=$(pwd)/infra/tfout.json ./infra/scripts/postprovision.sh
```

### 16.5 Rotating the Synapse SQL admin password

The Bicep auto-generates `sqlAdminPassword` on every deploy ([infra/modules/synapse/main.tf](../infra/modules/synapse/main.tf)). Treat the SQL login as a break-glass — runtime auth should be Entra-only (`-G` with `sqlcmd`).

The Synapse SQL admin password is generated by Terraform `random_password` and is stable per workspace. To rotate, taint the resource and re-apply: `terraform taint module.synapse.random_password.sql_admin && terraform apply -var-file=envs/<env>.tfvars`.

### 16.6 Re-embedding the corpus

Only required if you change the embedding model or its dimension. Procedure:

1. Snapshot existing index settings.
2. Drop and recreate the AI Search index with the new vector dimension.
3. Re-run ingestion against the source corpus.
4. Watch token spend — re-embedding the full corpus is the single biggest variable cost in this platform.

---

## 17. Troubleshooting

| Symptom | Likely cause | Resolution |
| --- | --- | --- |
| `terraform apply` fails on Foundry deployment with `Resource SKU not available` | Model not GA in Gov region. | Pick alternative `chat_deployment` / `chat_mini_deployment` / `embedding_deployment` or change region in your tfvars. |
| `terraform apply` fails with `InsufficientQuota` on Foundry | Quota not yet approved or below `capacity: 30`. | Submit / chase quota request in Gov; reduce `capacity` in [infra/modules/foundry/main.tf](../infra/modules/foundry/main.tf) only as a last resort. |
| `terraform apply` fails on `module.roles` with `AuthorizationFailed` | Your principal lacks `Microsoft.Authorization/roleAssignments/write`. | Get **Owner** or **User Access Administrator** at subscription scope. |
| `postprovision` fails with `403` against AI Search | RBAC not yet propagated to dev principal. | Wait 2–5 minutes and re-run `TFOUT_JSON=$(pwd)/infra/tfout.json ./infra/scripts/postprovision.sh`. |
| `/healthz` returns 503 | App didn't start. | `az webapp log tail`. Most common: missing/incorrect Entra authority for Gov ([§5.1](#51-mcp-server-entra-authority)). |
| `/mcp` returns 401 with valid commercial token | Wrong cloud. | Reissue token from Gov: `az account get-access-token --resource api://<siteName>` after `az cloud set --name AzureUSGovernment`. |
| `/mcp` returns 401 with valid Gov token | Audience mismatch. | Confirm `Auth__Audience` in App Service settings matches the `aud` claim of the token. |
| Function App: `403 Forbidden` from Graph | Admin consent not granted. | Tenant admin must grant `Sites.Read.All` / `Files.Read.All` to the ingestion managed identity ([§10.1](#101-get-microsoft-graph-admin-consent)). |
| Function App: empty result sets from Graph | Hitting commercial Graph from a Gov tenant. | Apply [§5.2](#52-ingestion-functions-microsoft-graph-base-url) and redeploy. |
| Sample client: `AADSTS50020` "user account does not exist in tenant" | Mixed-cloud auth — credentials cached for commercial cloud. | `az logout`, run [§6](#6-authenticate-to-azure-government), retry. |
| `query_structured_data` fails with `model not found` | `chatDeployment` parameter doesn't match an actual deployment in Foundry. | Confirm with `az cognitiveservices account deployment list ...` and reconcile. |
| `query_structured_data` fails with `Login failed for user` against Synapse | Synapse AAD admin not set, or principal not granted. | Confirm `principal_id` was set in your tfvars; re-run `terraform apply -var-file=envs/<env>.tfvars`. |
| App Service restarts but serves old or broken code after deploy | Package URL missing/expired or app settings drift. | `az webapp config appsettings list -n $APP -g $RG --query "[?name=='WEBSITE_RUN_FROM_PACKAGE']"` and verify the URL is reachable; then re-run §11 deploy steps to upload a new package and refresh the URL. |
| Foundry token cost alert fires unexpectedly | A user is asking very large `query_structured_data` questions. | Review App Insights traces for the `RagOrchestrator` and `SqlGenerator` source. Consider rate limits or per-user role gating. |
| `terraform destroy` fails with "Key Vault has soft-deleted resources" | Previous deploy left soft-deleted resources blocking re-create. | `az keyvault purge --name <kv-name>` (after confirming no production data), then re-run `terraform destroy`. |

---

## 18. Rollback and tear-down

### 18.1 Rolling back a code change

Application deploy is incremental. To roll back, redeploy from a known-good commit:

```bash
git checkout <known-good-sha>
# Re-run the App Service + Functions zip deploys from §11.
```

### 18.2 Rolling back infrastructure

Bicep deployments are versioned. To roll back, check out the prior `infra/` state and re-provision:

```bash
git checkout <known-good-sha> -- infra/
terraform apply -var-file=envs/<env>.tfvars
```

Note: destructive changes (deleting a resource, dropping CMK) are *not* automatically rolled back by re-running an older Bicep — the previously-existing resource will be recreated, but its data may be lost. Plan your changes accordingly.

### 18.3 Tear-down

```bash
terraform destroy -var-file=envs/<env>.tfvars
# Then purge soft-deleted Key Vault / Cognitive Services accounts manually:
#   az keyvault purge --name <kv-name>
#   az cognitiveservices account purge --name <foundry-name> --location <region> --resource-group <rg>
```

`--purge` removes soft-deleted Key Vault and Cognitive Services resources so the names can be reused. Drop `--purge` if you need the soft-delete safety net.

**Production tear-down checklist:**

- [ ] Confirm no users are connected to `/mcp`.
- [ ] Snapshot AI Search index (export documents) if any data needs to survive.
- [ ] Snapshot ADLS containers if any data needs to survive.
- [ ] Coordinate with ISSM for retention/disposition compliance.
- [ ] Run `terraform destroy -var-file=envs/<env>.tfvars` (and then purge soft-deleted vaults / Cognitive Services accounts) only after the above is documented.

---

## Appendix A — Required Azure RBAC roles

Created by [infra/modules/roleassignments/main.tf](../infra/modules/roleassignments/main.tf).

| Principal | Scope | Role |
| --- | --- | --- |
| MCP server identity | Storage account | Storage Blob Data Reader |
| MCP server identity | AI Search | Search Index Data Reader |
| MCP server identity | Foundry account | Cognitive Services OpenAI User |
| MCP server identity | Key Vault | Key Vault Secrets User |
| Ingestion identity | Storage account | Storage Blob Data Contributor |
| Ingestion identity | AI Search | Search Index Data Contributor |
| Ingestion identity | AI Search | Search Service Contributor |
| Ingestion identity | Document Intelligence | Cognitive Services User |
| Ingestion identity | Foundry account | Cognitive Services OpenAI User |
| Data Factory identity | Storage account | Storage Blob Data Contributor |
| Dev / CI principal *(if `principalId` set)* | Storage / Search / Foundry / KV | Owner-equivalent set for dev. |
| CMK consumers *(if `enableCmk=true`)* | Key Vault key | Key Vault Crypto Service Encryption User |

The identity running `terraform apply` must have **Owner** or **User Access Administrator + Contributor** at the subscription scope to create these.

---

## Appendix B — Required Microsoft Graph permissions

Required on the **ingestion** user-assigned managed identity. Application permissions; admin consent required in Flank Speed.

| Permission | Why it's needed |
| --- | --- |
| `Sites.Read.All` | Read SharePoint sites whose drives are listed in `SharePoint__DriveIds`. |
| `Files.Read.All` | Read drive items (files) referenced by `SharePoint__DriveIds` / `OneDrive__DriveIds`. |

If your tenant supports it, prefer **resource-specific consent** scoped to the exact sites you intend to ingest. This is significantly less risky than tenant-wide `Sites.Read.All`.

---

## Appendix C — Sovereign-cloud endpoint reference

| Service | Commercial | Azure Government |
| --- | --- | --- |
| Entra authority | `login.microsoftonline.com` | `login.microsoftonline.us` |
| Microsoft Graph | `graph.microsoft.com` | `graph.microsoft.us` |
| Azure Resource Manager | `management.azure.com` | `management.usgovcloudapi.net` |
| Storage DFS suffix | `dfs.core.windows.net` | `dfs.core.usgovcloudapi.net` |
| Storage Blob suffix | `blob.core.windows.net` | `blob.core.usgovcloudapi.net` |
| AI Search | `search.windows.net` | `search.azure.us` |
| Cognitive Services | `cognitiveservices.azure.com` | `cognitiveservices.azure.us` |
| App Service hostname | `azurewebsites.net` | `azurewebsites.us` |

`AzureAuthorityHosts.AzureGovernment` in the Azure SDK resolves to the correct authority. `environment().suffixes.storage` in Bicep resolves to the correct storage suffix for the cloud the deployment runs in — that's why the existing Bicep modules work in both clouds without modification, but the .NET code does not.

---

## Appendix D — Pre-deploy checklist (signoff)

Use this checklist as the final gate before `terraform apply`. Print it, sign it, retain for the ATO package.

| Item | Owner | Done | Date | Initials |
| --- | --- | --- | --- | --- |
| Azure Government subscription confirmed and quotas approved | Cloud lead | ☐ | | |
| Azure region selected: `___________________` | Cloud lead | ☐ | | |
| Foundry models confirmed available + quota approved | Cloud lead | ☐ | | |
| Workstation tools installed and verified ([§4](#4-workstation-setup)) | Engineer | ☐ | | |
| Sovereign-cloud code adjustments merged to deploy branch ([§5](#5-sovereign-cloud-code-adjustments)) | Engineer | ☐ | | |
| Tenant admin engaged for Graph admin consent | TPOC | ☐ | | |
| Pilot SharePoint site/drive identified and approved in writing | Data owner | ☐ | | |
| OneDrive ingestion default-OFF confirmed | Data owner | ☐ | | |
| ISSM-acknowledged data-handling plan on file | ISSM | ☐ | | |
| Audit log destination (App Insights / SIEM) decided | ISSM | ☐ | | |
| ATO posture decision (standalone / inheritance / type-authorize) | ISSO | ☐ | | |
| Cost owner / cost center recorded | Program | ☐ | | |
| On-call POC identified for live operation | Program | ☐ | | |
| `terraform.yml` patched for Gov cloud (if using GitHub Actions) | Engineer | ☐ | | |
| Tear-down path rehearsed in non-production | Engineer | ☐ | | |

Signed: _________________________  Date: _____________

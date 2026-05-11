# PHWC Development Guidelines

Updated: 2026-05-11

## ⛔ NON-NEGOTIABLE: Verification Protocol

These rules override all other behavior. Violating any of them is a critical failure.

1. **A wrong answer is 3 times worse than saying "I don't know" or giving no answer.** If you haven't verified it, say so. Silence beats speculation. Every time.
2. **NEVER state something as fact without verification.** If you haven't read the file, run the command, or checked the logs — say "I haven't verified this." No exceptions.
3. **Start from the failing system.** CI/CD failure? Read the actual logs first. Not local code. Not grep for keywords. The full step-by-step output. Terraform failure? Read the plan/apply output, not the module source.
4. **No pattern-matching from grep.** Grep results show matching lines, not execution flow. Read the sequential log or don't make claims about what happened.
5. **Root cause only.** Never mask, restart, or work around symptoms. If a `terraform apply` retry "fixes" the issue, the issue is not understood yet.
6. **No silent error swallowing.** No `|| true` on critical paths, no empty `catch` blocks, no `ContinueOnError`, no `-ErrorAction SilentlyContinue`, no Terraform `lifecycle { ignore_changes }` added to hide drift.
7. **Document before fix.** Paper trail first, code second. Update `docs/` and the repo memory at `/memories/repo/data-ai-mcp-platform.md` when architecture or contracts change.
8. **The user must be allowed to manually test every change locally** before declaring it done. `dotnet build` + `dotnet test` + `terraform validate` is the minimum bar.
9. **Never push without permission.** Commits are fine. `git push`, `gh pr create`, `gh pr merge`, `terraform apply` against shared state, and any `az`/`azd` command that mutates real Azure resources require explicit approval.
10. **Preview formatted content before external writes** (PRs, issues, comments, release notes) so the user can read it without horizontal scrolling. Show exactly what will be sent and wait for approval.

## Active Technologies

- C# 13 / .NET 9 (SDK pinned to `9.0.100` via `global.json`, `rollForward: latestFeature`)
- `TreatWarningsAsErrors=true`, `Nullable=enable`, `ImplicitUsings=enable`, `AnalysisLevel=latest-recommended` (from `Directory.Build.props`)
- Central Package Management via `Directory.Packages.props` — no per-project `<PackageReference Version="…" />`
- ASP.NET Core for `src/DataAiMcp.McpServer/` (Model Context Protocol server, OBO auth, RAG over Azure AI Search)
- Azure Functions isolated worker (FlexConsumption) for `src/DataAiMcp.Ingestion.Functions/`
- Microsoft.Graph SDK for SharePoint / OneDrive ingestion in `src/DataAiMcp.Ingestion.Functions/Graph/`
- Azure AI Search (`Azure.Search.Documents`) with per-index CMK and dual-region writer (`IIndexWriter`)
- Azure AI Foundry (`Microsoft.Extensions.AI` + `azapi @2025-04-01-preview` for provisioning)
- Azure Synapse Serverless SQL (T-SQL views over Delta in ADLS Gen2 `curated` filesystem)
- Azure Document Intelligence for layout/OCR
- Azure Front Door Standard for primary/secondary regional routing
- Key Vault + CMK (opt-in via `enable_cmk = true`)
- Terraform `hashicorp/azurerm ~> 4.18`, `Azure/azapi ~> 2.2`, `hashicorp/random ~> 3.6`
- TFLint with `azurerm` + `terraform` recommended preset (`.tflint.hcl` at repo root)
- GitHub Actions with OIDC federated identity (no client secrets)

## Project Structure

```text
DataAiMcp.slnx                    # Solution (slnx format)
Directory.Build.props             # Global C# build settings + warning policy
Directory.Packages.props          # Central Package Management
global.json                       # .NET SDK pin (9.0.100)
src/
  DataAiMcp.Shared/               # Cross-cutting: Ai, Auth, Documents, Search, Storage, Telemetry, DI
  DataAiMcp.McpServer/            # ASP.NET Core MCP server (Auth, Rag, Synapse, Tools, Resources)
  DataAiMcp.Ingestion.Functions/  # Azure Functions: IngestBlob, OneDriveFiles, SharePointFiles, Curation
  DataAiMcp.Tools.IndexProvisioner/ # One-shot console: create/update AI Search indexes
  Samples/DataAiMcp.SampleClient.Console/ # Reference MCP client
tests/
  DataAiMcp.Shared.Tests/         # MarkdownChunker, etc.
  DataAiMcp.McpServer.Tests/      # HealthEndpointTests, etc.
  DataAiMcp.Functions.Tests/      # IngestionPipelineSmokeTests
  DataAiMcp.Smoke.Tests/          # End-to-end smoke against deployed env
infra/
  *.tf                            # Root composition (main, primary, secondary, frontdoor, roles, …)
  envs/{dev,prod}.tfvars          # Per-environment inputs
  modules/{alerts,appservice,cmk,datafactory,documentintelligence,foundry,frontdoor,
           functions,identity,keyvault,monitoring,regional,roleassignments,search,
           shirhost,storage,synapse}/ # 17 modules
  bootstrap/                      # Run-once: provisions remote tfstate backend (local state)
  datafactory/pipelines/          # ADF pipeline JSON
  synapse/views/                  # Synapse Serverless T-SQL view definitions
  scripts/postdeploy.sh           # Post-apply finalization
  scripts/postprovision.sh        # Post-provision finalization
docs/                             # DEPLOYMENT.md, DEVELOPMENT.md, INGESTION.md + per-source guides
.github/workflows/                # ci.yml, cd.yml, terraform.yml, terraform-destroy.yml
```

## Commands

```bash
# Build + test (.NET 9)
dotnet build DataAiMcp.slnx
dotnet test  DataAiMcp.slnx

# Functions: use VS Code tasks (NOT raw dotnet run)
#   "build (functions)"   → builds src/DataAiMcp.Ingestion.Functions
#   "publish (functions)" → Release publish for zip-deploy
#   "func: 4"             → host start against the build output

# Terraform — always from infra/
cd infra
terraform fmt -check -recursive
terraform init -backend=false        # local validation only; never points at real state
terraform validate
tflint --recursive

# Terraform — real backend (requires bootstrap outputs in env)
cd infra
terraform init \
  -backend-config="resource_group_name=$TFSTATE_RESOURCE_GROUP" \
  -backend-config="storage_account_name=$TFSTATE_STORAGE_ACCOUNT" \
  -backend-config="container_name=$TFSTATE_CONTAINER" \
  -backend-config="key=phwc-$ENV.tfstate"
terraform plan  -var-file="envs/$ENV.tfvars" -out=tfout
terraform apply tfout

# Deploy app code (after terraform apply)
az webapp deploy           --resource-group "$RG" --name "$MCP_APP"      --src-path mcpserver.zip --type zip
az functionapp deployment source config-zip \
                           --resource-group "$RG" --name "$FUNC_APP"     --src functions.zip
```

## Code Style

- **C#**: nullable enabled, implicit usings, file-scoped namespaces, `latest` LangVersion. Warnings are errors — fix them, don't suppress with `#pragma`. The repo-wide `NoWarn` list in `Directory.Build.props` is the only sanctioned suppression set; expanding it requires justification.
- **Central Package Management**: add versions to `Directory.Packages.props` only. Per-project `<PackageReference>` must omit `Version=`.
- **Tests**: xUnit. Tests live in `tests/DataAiMcp.<Project>.Tests/`. Smoke tests against deployed Azure go in `tests/DataAiMcp.Smoke.Tests/` and must not run by default in CI without env vars.
- **MCP server tools**: register in `src/DataAiMcp.McpServer/Tools/`; security-trim through `CallerSecurityContext` + `RagOrchestrator.SearchAsync(query, top, source, callerSecurityIds, ct)`. Never return documents without applying the `securityIds/any(...)` filter.
- **Ingestion pipeline**: source-specific fetchers under `src/DataAiMcp.Ingestion.Functions/Graph/`; the shared pipeline is in `src/DataAiMcp.Ingestion.Functions/Pipeline/`. `securityIds` blob metadata is the contract — defaults to `["__org__"]` for non-Graph sources.
- **Terraform**:
  - Always run `terraform fmt -recursive` before commit
  - Use `azurerm_storage_data_lake_gen2_filesystem` for ADLS Gen2, **not** `azurerm_storage_container` (shared-key is disabled)
  - Use `azapi` only where `azurerm` lacks coverage: Foundry account/project/connections/deployments (`@2025-04-01-preview`), Search CMK enforcement (`@2024-06-01-preview`), Functions FlexConsumption (`@2024-04-01`)
  - Provider block must include `features {}` and `storage_use_azuread = true`
  - Foundry model deployments must keep their explicit `depends_on` chain (mimics Bicep `@batchSize(1)`); removing it WILL cause concurrent deployment failures
  - New modules go under `infra/modules/<name>/` and are composed from the root, never nested inside another module
- **Secrets**: never commit. GitHub Secrets: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`. GitHub Variables: `TFSTATE_RESOURCE_GROUP`, `TFSTATE_STORAGE_ACCOUNT`, `TFSTATE_CONTAINER`. Environments: `dev`, `prod` with required-reviewers gate.
- **No `:latest` image tags** in any deployable artifact.

## Engineering Principles

### Holistic Thinking

Before writing any code, trace the impact through the full stack:

- Terraform module → root composition → tfvars → CI workflow → app config → runtime behavior → tests → docs
- Ingestion: source connector → `DocumentIngestionPipeline` → blob metadata (`securityIds`) → AI Search index → `RagOrchestrator` filter → MCP tool response
- Verify contract alignment against the **current** implementation, not historical Bicep assumptions. The repo migrated from Bicep to Terraform; resource names use a SHA1-based `resource_token` that does NOT match Bicep `uniqueString` — first apply on a previously-Bicep-deployed environment WILL rename resources.
- Update `docs/` and the repo memory at `/memories/repo/data-ai-mcp-platform.md` whenever architecture or contract reality changes.

### Senior Developer Mindset

- Act like a senior developer / tech lead, not a checklist executor
- Audit every diff as if you were the reviewer
- Anticipate edge cases (CMK enabled, DR enabled, Gov cloud, groups overage claim) before they land
- Flag design tension and drift explicitly — e.g., `random_password` with `keepers = { workspace = … }` is intentionally stable, unlike Bicep `newGuid()`; call this out when touching it

### Root Cause Only

- Fix root causes rather than masking symptoms
- If `terraform apply -refresh-only` or a re-run hides the issue, the issue is not understood yet
- If a test passes only after a retry, treat it as failing
- The known-flaky surfaces (Foundry deployment chaining, FDID pinning, groups overage) are documented in `/memories/repo/data-ai-mcp-platform.md` "Known gaps / follow-ups" — extend that list, don't paper over

### Document Before Fix

- Create or update the paper trail before implementing the change
- Keep `docs/`, `README.md`, `infra/<module>/README.md` (where present), and `/memories/repo/data-ai-mcp-platform.md` synchronized with the actual architecture
- Terraform variable additions/removals must be reflected in `infra/envs/*.tfvars` and the deployment docs in the same change

## Session Procedures

This repo does not use spec-kit. Treat each task as ad-hoc unless the user references a specific doc in `docs/`. When the user asks about deployment, start from `docs/DEPLOYMENT.md`; for development setup, `docs/DEVELOPMENT.md`; for ingestion sources, `docs/INGESTION.md` and the per-source guides in `docs/ingestion/`.

The persistent repo notes live at `/memories/repo/data-ai-mcp-platform.md` — read it at the start of any non-trivial task involving Terraform modules, the ingestion pipeline, or the RAG security model.

# Data + AI + MCP Platform — Federal Agency

> A turnkey Azure reference platform that unifies the unstructured documents and structured engineering & logistics data spread across a **federal agency** behind a single secure **Model Context Protocol (MCP)** endpoint — so any LLM, agent, or copilot used by the agency can answer grounded questions about combat-system in-service engineering, lifecycle logistics, fleet readiness, and technical guidance without bespoke integration work for each system.

> **Scope note.** This reference architecture is intended to be deployed into **Flank Speed** (the DON's Microsoft 365 GCC High tenant) and the matching **Azure Government** subscription it federates with. It targets **unclassified CUI workloads** at IL4 / IL5. Classified data on SIPR / JWICS is out of scope. The Terraform modules are region-agnostic and deploy into Azure Government with the same `terraform apply` invocation, but several config touch-points (Graph base URL, Entra authority, model availability) must be set to their US-Gov sovereign equivalents — see [Decisions you need to make before `terraform apply`](#decisions-you-need-to-make-before-azd-up) and [Pitfalls — read this section twice](#pitfalls--read-this-section-twice) below.

---

## The problem at the warfare center

A federal agency responsible for in-service engineering and lifecycle logistics across a large portfolio of mission systems runs on data that is fragmented across many authoritative systems:

- **Federal agency technical documentation, technical manuals, ISEA work packages, SHIPALTs, OrdAlts, ECPs, PMS feedback, and TRDs** in SharePoint Online libraries hosted in **Flank Speed** (M365 GCC High).
- **OPNAV / SECNAV / NAVSEA instructions, command policies, safety bulletins, and warfare-center SOPs** in Flank Speed SharePoint libraries and OneDrive working drafts.
- **Maintenance and logistics records** (3M / PMS data, fleet casualty reports, ILS records, supply transactions) landed nightly into Azure SQL Managed Instance from authoritative systems.
- **Engineering tickets, distance-support cases, and program-office tracking data** in Dataverse / Power Platform apps used by the warfare center's departments.
- **Test data, range exports, and contractor deliverables** delivered by file share into Azure Files or ADLS.

Today, none of this is reachable through an AI surface. Every question that crosses two of those systems is answered the same way: a person opens SharePoint, opens a SQL client, opens Dataverse, opens a file share, and stitches the answer together by hand. Engineers and analysts spend hours on lookups that the data already supports, the same questions get researched repeatedly across departments, and there is no governed, reusable path for any future copilot or AI assistant the warfare center's leadership might want to stand up — which is exactly the gap the **CDAO**, **Task Force Lima**, and **DON CIO AI guidance** call out.

## What this platform does

This repository is a single deployable solution that:

1. **Ingests** documents and tabular data from the systems the federal agency already uses — Flank Speed SharePoint / OneDrive, SQL MI, Dataverse, Azure Files, and any drop-folder source.
2. **Curates and indexes** the data inside the warfare center's Azure Government tenant — text into Azure AI Search, tables into Synapse serverless SQL views over Parquet in ADLS Gen2.
3. **Exposes** the unified corpus through one Entra-protected MCP server so any compliant client (GitHub Copilot, VS Code, Microsoft 365 Copilot agents, custom bots, the official MCP SDKs) can call it.
4. **Secures** every hop with Entra ID, user-assigned managed identities, least-privilege RBAC, optional customer-managed-key (CMK) encryption, and full Application Insights traces — aligned to the controls a federal agency ISSM / ISSO will look at.

You run `terraform apply` once. You get a production-shaped, mission-aligned data + AI + MCP stack inside the warfare center's own subscription.

## Why it matters for a federal agency

| Capability | What it means for the warfare center |
| --- | --- |
| **One protocol, every client** | Combat-systems engineers, logisticians, distance-support analysts, and program-office staff all hit the same MCP endpoint from whatever AI client their department has approved — no per-tool integration work. |
| **Both unstructured *and* structured data** | An ISEA can ask for the **MRC** *and* the latest open casualty reports against the same equipment in one turn. |
| **Grounded answers with citations** | Hybrid RAG (BM25 + vector + semantic rerank) returns chunks with source links, so the model cites the **NAVSEA technical manual**, **OPNAVINST**, or **ISEA work package** it relied on — auditable for safety-of-ship contexts. |
| **Stays inside your tenant** | The model talks to the MCP server, the MCP server talks to your data — your CUI / FOUO content does not leave the warfare center's Azure boundary. |
| **Governed by default** | Entra JWT on `/mcp`, managed identities for every service-to-service hop, role-based access, optional CMK, Key Vault, App Insights — the controls an ATO package needs to check. |
| **Operationally complete** | Terraform IaC (15 modules + remote state bootstrap), GitHub Actions OIDC pipelines (no client secrets, plan-on-PR + environment-gated apply), smoke tests, post-deploy hooks, and clean tear-down — not a science project. |
| **Extensible by federal agency teams** | New tools are a class drop-in; new sources are an ADF copy activity or a blob upload to `landing/`. |

## What you can do with it

Once deployed, federal agency staff (or their copilots) can ask things like:

> *"Summarize the latest safety bulletin for the combat system I'm working on and link to the source."*
> → `search_documents` returns chunks from the SharePoint-ingested PDF with citations back to the Flank Speed document library.

> *"Show me open Priority-1 casualty reports against the systems this division is the ISEA for, in the last 30 days."*
> → `query_structured_data` translates the question to T-SQL, runs it against the curated SQL MI snapshot via Synapse serverless, and returns rows + the SQL it generated for the analyst to inspect.

> *"For ships in availability supported by the federal agency this quarter, list the open ECPs and any associated ISEA technical guidance."*
> → The agent calls `query_structured_data` *and* `search_documents` in the same turn, joining structured availability data with unstructured engineering documents.

> *"What does OPNAVINST 5100.19 say about confined-space entry, and which warfare-center SOPs reference it?"*
> → Pure document RAG via `search_documents`, with citations across both the OPNAV instruction and the local SOP that inherits from it.

> *"What sources are connected, and what fields are available on `federal_agency_casreps`?"*
> → `list_sources` and `describe_dataset` give the agent (and the user) a self-describing catalog so they don't have to guess schema.

The five MCP tools shipped today:

| Tool | Purpose |
| --- | --- |
| `search_documents` | Hybrid search over the unified document index (instructions, technical manuals, ISEA work packages, SOPs, bulletins). |
| `get_document` | Pull the full ordered chunks of a single document — useful when an agent needs the entire instruction or work package, not just the top chunk. |
| `query_structured_data` | NL → T-SQL over Synapse serverless views (CASREPs, 3M / PMS, ILS, supply); returns rows + the generated SQL for analyst review. |
| `describe_dataset` | Self-describing catalog of available tables. |
| `list_sources` | Self-describing catalog of connected systems. |

Add warfare-center-specific tools by dropping a class into `src/DataAiMcp.McpServer/Tools/` and registering it in `Program.cs`. The MCP framework picks it up automatically — useful for things like a `lookup_nsn` tool against the supply system, a `get_pms_schedule` tool against 3M, a `lookup_isea_work_package` tool against the engineering library, or a `query_distance_support` tool against the case management system.

## What gets connected at the federal agency

Out of the box the platform pulls from the systems most federal agency departments already operate inside their Flank Speed / Azure Government subscription:

- **Flank Speed SharePoint Online (M365 GCC High)** — federal agency technical documentation libraries, ISEA work-package sites, command instructions, agency SOPs, and safety bulletins. Microsoft Graph endpoints live on `graph.microsoft.us`, not `graph.microsoft.com`.
- **Flank Speed OneDrive for Business** — engineer working drafts and staff documents (with command policy on what may be ingested; OneDrive content is often pre-decisional and a frequent source of accidental over-sharing).
- **Dataverse (GCC High)** — engineering tickets, distance-support cases, and program-office tracking apps built on Power Platform.
- **Azure SQL Managed Instance** — nightly Parquet snapshots of CASREPs, 3M / PMS, ILS, and supply tables.
- **Azure Files / ADLS Gen2** — drops from on-prem systems, range/test exports, and contractor deliverables.

Anything written into the `landing/` container is automatically picked up by the ingestion pipeline (Document Intelligence → chunking → embedding → AI Search). That makes it trivial to wire in additional sources — a department's project tracker, a program office's after-action repository, a contractor deliverables share — by writing a single ADF copy activity or a custom upstream job.

## How a request flows

```
┌───────────────────────┐                         ┌──────────────────────────────────┐
│  MCP client           │ ── HTTPS + Entra JWT ──►│  ASP.NET Core MCP server         │
│  (Copilot, VS Code,   │   (CAC-backed identity  │  (App Service, /mcp endpoint)    │
│   command bot, agent) │    via Entra ID)        │                                  │
└───────────────────────┘                         │  search_documents ──► AI Search  │
                                                  │  query_structured ──► Synapse    │
                                                  │  list_sources / describe_dataset │
                                                  └──────────────────────────────────┘
                                                              │
                                  ┌───────────────────────────┴──────────────────────┐
                                  ▼                                                  ▼
                       ┌────────────────────┐                          ┌────────────────────────┐
                       │  Azure AI Search   │                          │  Synapse Serverless     │
                       │  (chunks + vectors,│                          │  (views over Parquet    │
                       │   citations)       │                          │   in `curated/`)        │
                       └────────────────────┘                          └────────────────────────┘
                                  ▲                                                  ▲
                                  │ embeddings + metadata                            │
                       ┌──────────┴───────────┐                                      │
                       │  Ingestion Functions │  ─────── curated Parquet ────────────┘
                       │  + Document Intel.   │
                       └──────────┬───────────┘
                                  │
                       ┌──────────┴────────────┐
                       │  ADLS Gen2 (landing/  │
                       │  raw/curated/chunks)  │
                       └──────────┬────────────┘
                                  │
        ┌────────────┬────────────┴────────────┬────────────────┐
        ▼            ▼                         ▼                ▼
  SharePoint /   Azure Data Factory       Dataverse        Azure SQL
  OneDrive       (SQL MI, Files,          (PowerApps /     Managed
  (Flank Speed   range/inventory drops)   facility data)   Instance
   Graph .us)
```

Every hop in that diagram authenticates with **managed identities** — no shared secrets, no service accounts, no key files on disk. The dev principal who runs `terraform apply` is granted the data-plane roles needed to test from their workstation; the deployed services use their own identities from there on.

For a deeper look at how each data source flows in, see the **[Ingestion guide](INGESTION.md)** and the per-source cookbooks under [`docs/ingestion/`](ingestion/).

## Who it's for

- **Federal agency departments** (Combat Systems, In-Service Engineering, Logistics, Distance Support, Test & Evaluation, etc.) that want a sanctioned "AI on top of our engineering data" pattern they can hand to product teams instead of letting each team build its own.
- **Federal agency IT / N6 / ISSM staff** who need an AI surface area they can authorize once and let multiple departments and programs consume — instead of reviewing one bespoke RAG app per team.
- **Program-office and contractor application teams** building copilots or chat experiences who need grounded answers without standing up their own indexing stack.
- **Architects and SEs** evaluating MCP as the integration contract for the warfare center's internal AI surface area, including the migration path to Azure Government for higher impact levels.

## Decisions you need to make before `terraform apply`

Deploying into Flank Speed / Azure Government is not "the same as commercial with a different region name." The following decisions need to be made up front — most of them are configuration choices, not code changes, but getting them wrong means a rip-and-replace later.

### Tenant & subscription

- **Azure Government subscription** — confirm the command has (or can get) an **Azure Government** subscription federated with the Flank Speed Entra tenant. Commercial Azure subscriptions cannot consume Flank Speed identities cleanly and will not satisfy IL4/IL5 boundary requirements.
- **Subscription scoping** — decide whether this lands in a per-department subscription, a directorate-shared subscription, or an agency-wide platform subscription. This drives ATO boundary, billing, and who can grant the role assignments [infra/modules/roleassignments/main.tf](../infra/modules/roleassignments/main.tf) creates.
- **Resource group naming / tagging** — align with the federal agency's existing naming standards before the first `terraform apply`; the resource-group name is encoded into the deployment and is not trivial to change.

### Region & service availability

- **Azure Government region** — pick a region (typically `usgovvirginia` or `usgovarizona`) where **all** of the following are simultaneously available: AI Foundry / Azure OpenAI with the model you intend to use, Document Intelligence, AI Search semantic ranker, Synapse serverless, and Flex-Consumption Functions. Service availability in Gov lags commercial; verify before committing.
- **Foundry model selection** — `gpt-4o`, `gpt-4o-mini`, and `text-embedding-3-large` may not all be GA in your chosen Gov region on the date you deploy. Decide a fallback set (e.g., the latest available chat model + a supported embedding model) and set `chat_deployment`, `chat_mini_deployment`, `embedding_deployment` in your [infra/envs/<env>.tfvars](../infra/envs/) before the first apply. Re-embedding later is expensive — pick once.
- **Quota** — Foundry quota in Gov regions is requested separately from commercial. Submit the quota request before the deployment window.

### Identity & sovereign-cloud endpoints

- **Entra authority** — Flank Speed identities authenticate via `login.microsoftonline.us`, not `login.microsoftonline.com`. The MCP server's JWT validation in [src/DataAiMcp.McpServer/Program.cs](../src/DataAiMcp.McpServer/Program.cs) uses `https://login.microsoftonline.com/{tenant}/v2.0` today — that **must** be changed to the `.us` authority for Gov, and the JWT issuer/audience validation parameters re-checked.
- **Microsoft Graph base URL** — the Graph client factory in [src/DataAiMcp.Ingestion.Functions/Graph](../src/DataAiMcp.Ingestion.Functions/Graph) must be configured for `https://graph.microsoft.us`. Hitting commercial Graph from a Gov tenant fails authentication or returns no data.
- **App registration audience** — the deployed audience pattern is `api://<siteName>`. Decide whether to keep that or front the MCP server with a command-managed app registration that exposes a named scope (e.g., `MCP.Read`) — preferred for production because it lets ISSM scope which user populations get tokens.
- **Conditional Access** — Flank Speed enforces tenant-wide Conditional Access policies (CAC, compliant device, location). Decide which user populations are permitted to call the MCP server and surface that to your ISSO when scoping the app registration.

### Data classification & ingestion policy

- **What may be ingested** — Flank Speed contains a wide range of CUI categories. Decide *before* turning on the SharePoint connector which sites/libraries are in scope. Ingesting an entire tenant by accident is the single biggest risk in this pattern.
- **Per-source allow lists** — `SharePoint__DriveIds`, `OneDrive__DriveIds` are explicit. Treat them as a security boundary, not a convenience setting. Default to empty; add IDs only after the owning command has signed off in writing.
- **Privacy / PII screening** — decide whether the ingestion pipeline should run a redaction step (PII, names, NSNs flagged as sensitive, hull/USS identifiers) before chunks are embedded and indexed. Document Intelligence supports it; the current pipeline does not enable it.
- **Retention & disposition** — chunks land in `chunks/` and the AI Search index. Decide how source-document deletes propagate to the index (today: not automatically). Wire up a tombstoning job before users depend on the platform.

### Authorization model

- **Who calls the MCP server** — is it the human user (delegated, on-behalf-of) or a service agent (app-only)? The current code validates JWTs but does not enforce per-user document trimming. Decide whether to:
  1. Live with **tenant-wide trimming** (anyone authenticated can search anything ingested) — simple, but every consumer must inherit the most restrictive ingest policy, *or*
  2. Implement **security-trimmed search** (group-membership filters on each query) — accurate, but requires capturing ACLs at ingest time and adding filter clauses in [src/DataAiMcp.McpServer/Rag/RagOrchestrator.cs](../src/DataAiMcp.McpServer/Rag/RagOrchestrator.cs).
- **App role definitions** — `DataAiMcp.Admin` is the only privileged role today. Decide whether you need scoped reader roles (e.g., `DataAiMcp.Reader.CombatSystems`, `DataAiMcp.Reader.Logistics`, `DataAiMcp.Reader.DistanceSupport`) and how Entra groups map to them.

### Networking & boundary

- **Public ingress vs. Private Endpoint only** — the default Terraform gives the App Service a public hostname. For a Gov-side production deployment, decide whether to disable public access and front the service with **Private Endpoint + Front Door / App Gateway with WAF**, terminating only on the warfare center's enclave.
- **Egress controls** — the Function App pulls from Graph, Document Intelligence, Foundry, AI Search, and Storage. Decide whether outbound traffic is allowed to traverse the public path inside Gov, or whether VNet integration + Private Endpoints are required.
- **Customer-managed keys (CMK)** — decide CMK on/off (`enableCmk` parameter) before first deploy. Switching from MSP-managed to CMK after the fact is non-trivial on AI Search in particular.

### Operations & assurance

- **ATO posture** — is this a **standalone ATO**, an **ATO inheritance** from a parent platform (e.g., a federal enterprise environment), or **RMF Type-Authorize** of the pattern itself? This drives the artifacts you need to produce alongside the code.
- **Audit log destination** — App Insights and Log Analytics are deployed by default. Decide whether logs need to ship to the federal agency's SIEM (Splunk, Sentinel-Gov, etc.) and configure the diagnostic settings before users hit the system.
- **Backup & DR** — `secondaryLocation` enables multi-region in Gov as well, but only if the second region has the same service availability as the primary. Decide if DR is required or if RTO/RPO can be met by re-ingestion.

## Pitfalls — read this section twice

These are the failures most likely to bite a Flank Speed / Azure Government deployment. Several of them have nothing to do with the code in this repo and everything to do with the environment.

1. **Hard-coded commercial endpoints.** The current source assumes commercial Azure: the Entra authority in [src/DataAiMcp.McpServer/Program.cs](../src/DataAiMcp.McpServer/Program.cs) is `login.microsoftonline.com`, the Graph SDK in [src/DataAiMcp.Ingestion.Functions/Graph](../src/DataAiMcp.Ingestion.Functions/Graph) defaults to `graph.microsoft.com`, and `DefaultAzureCredential` defaults to the public cloud authority. **Every one of these must be retargeted to `.us` equivalents before you can authenticate in Gov.** Symptoms when you forget: 401s with no helpful error text, empty Graph result sets that look like permissions issues, and `AADSTS50020` "user account does not exist in tenant" errors.

2. **Foundry model availability gaps.** Don't assume the model named in `chat_deployment` exists in your chosen Gov region. Provisioning will *succeed* with a deployment of the wrong model name (Terraform doesn't know better), but `query_structured_data` will fail at runtime with a model-not-found error. Verify model availability in the Azure Government model catalog **before** running `terraform apply`.

3. **Graph permissions admin consent.** Graph application permissions (`Sites.Read.All`, `Files.Read.All`) require **Flank Speed tenant admin consent**. The federal agency cannot self-consent. Plan for a multi-day cycle to get admin consent through the appropriate DON CIO / Flank Speed support channel; do not start the project assuming you can grant this yourself.

4. **Ingesting the wrong tenant scope.** It is trivially easy to set `SharePoint__DriveIds` to a drive that contains data the federal agency did not intend to expose to AI (or that belongs to another organization sharing the tenant). The tools you ship will happily search across whatever was indexed. Treat the connector configuration as a controlled artifact: gate it through the same review the federal agency applies to data-sharing agreements, and start with a single explicitly-named pilot library.

5. **OneDrive over-collection.** OneDrive for Business often contains pre-decisional drafts, personnel-action documents, and content the user copied from email. Even with a narrow drive list, indexing a OneDrive into a shared search index can over-share content across the tenant. Default position should be **OneDrive ingestion off** until a clear use case + ISSM sign-off exists.

6. **Mixing tenants.** A common mistake is to deploy the Azure Government subscription, but configure the app registration in the *commercial* Entra tenant by accident (e.g., because the developer's commercial credentials are still cached). Tokens will not validate. Always run `az cloud set --name AzureUSGovernment` and `az login --tenant <flank-speed-tenant-id> --use-device-code` after explicitly logging out of commercial credentials, and set `provider "azurerm" { environment = "usgovernment" }` in [infra/main.tf](../infra/main.tf). Verify with `az account show --query tenantId` before any deploy.

7. **CAC + Conditional Access blocking the dev loop.** Flank Speed Conditional Access often requires CAC + compliant device for interactive sign-in. The sample client in [src/Samples/DataAiMcp.SampleClient.Console](../src/Samples/DataAiMcp.SampleClient.Console) uses `DefaultAzureCredential`, which will trigger device-code or interactive flows and may be blocked. Plan to use `AzureDeveloperCliCredential` or service-principal-based flows on a compliant workstation, and budget for a "this credential type is not allowed" finding during the first attempt.

8. **MCP client compatibility in Gov.** Not every commercial-cloud MCP client is wired for `.us` endpoints. GitHub Copilot Enterprise, Copilot Studio, and Microsoft 365 Copilot have different availability stories in Gov. Validate that the *intended* client population can actually reach the deployed `/mcp` endpoint with a Flank Speed-issued token *before* committing user-facing dates.

9. **PII / classification spillage in chat completions.** `query_structured_data` sends the user's question and a schema description to Foundry to generate SQL, then sends the resulting rows back to Foundry to summarize. Decide whether row-level data may transit the model — if not, run the SQL and return raw rows without an LLM-generated summary. This is a one-line behavioral change in [src/DataAiMcp.McpServer/Tools/StructuredTools.cs](../src/DataAiMcp.McpServer/Tools/StructuredTools.cs) and should be explicit.

10. **No security trimming today.** As shipped, every authenticated caller can query every indexed chunk. If the corpus contains documents the calling user would not have access to in SharePoint, you have an over-share. Until ACL-aware trimming is implemented, the safe operating mode is: **only ingest documents the entire authorized user population is already cleared to read.**

11. **Re-ingestion cost surprises.** Switching the embedding model means re-embedding every chunk. Across the federal agency's full technical-documentation corpus this is non-trivial in tokens and dollars. Pick the embedding model (and dimension) once, write it down in the ATO artifacts, and treat it as a versioned decision.

12. **Shadow copies in `landing/`.** The `landing/` container is the easiest extensibility seam — and the easiest place to land a file that should not have been ingested. Apply lifecycle management (auto-delete after N days), enable storage diagnostic logging, and review who has write access to the container as part of the deploy checklist.

13. **`terraform destroy` + `az keyvault purge` and CMK keys.** With CMK enabled, `az keyvault purge` after destroy will remove the encryption key. If the storage account or AI Search index encrypted with that key still has data references elsewhere, you will lose access. Tear-down rehearsals belong on a non-production environment first.

14. **Cost telemetry blind spots.** App Insights captures HTTP traffic but not Foundry token spend by default. Enable Foundry diagnostic settings to Log Analytics and create a cost alert on the Foundry account before opening the platform to a user population — token usage in `query_structured_data` scales with question complexity, not user count.

## Security & compliance posture

This is a reference implementation, not an authorization package — but it is deliberately built on the controls a Navy ATO will examine:

- **Identity** — Entra ID with JWT validation on `/mcp`; user-assigned managed identities for App Service, Functions, and Data Factory; no static credentials anywhere.
- **Authorization** — RBAC on every Azure data plane (Storage, AI Search, Foundry, Document Intelligence, Synapse, Key Vault) wired in [infra/modules/roleassignments/main.tf](../infra/modules/roleassignments/main.tf). MCP-level policies (`ReadDocuments`, `QueryStructured`, `AdminTools`) live in [src/DataAiMcp.McpServer/Auth](../src/DataAiMcp.McpServer/Auth).
- **Encryption** — TLS in transit; Microsoft-managed keys at rest by default; opt-in **customer-managed keys** via Key Vault for Storage, AI Services, AI Search, and Synapse (`enableCmk` parameter).
- **Auditing & telemetry** — Application Insights + Log Analytics on every service; OpenTelemetry traces from the MCP server; tool calls are observable end-to-end.
- **Data residency** — every byte stays in the Azure region you pick. Multi-region DR is opt-in via the `secondaryLocation` parameter.
- **Government cloud** — the Terraform is region-agnostic and deploys into Azure Government with the same `terraform apply` invocation, given an appropriately scoped subscription and Foundry availability. Pair with command-level network controls (Private Link, hub-spoke, NSGs) for a production posture.

Before exposing the platform to live users, walk through the standard checklist with your ISSM: data-tagging policy for what may be ingested, retention/disposition rules, audit log shipping to your SIEM, and whether the workload requires CUI or FOUO handling controls.

### Zero Trust posture

This platform is built for Zero Trust **inside the Flank Speed / Azure Government tenant boundary**. The boundary itself is defined by Azure Government (the network — IL5 sovereign cloud, `.us` service endpoints, no commercial-internet ingress) and by Flank Speed Conditional Access (the user population — CAC, compliant device, location, MFA). The codebase enforces the three Zero Trust tenets *within* that boundary:

- **Verify explicitly** — every `/mcp` call requires a Flank Speed-issued Entra JWT validated for issuer, audience, lifetime, and signing key in [src/DataAiMcp.McpServer/Program.cs](../src/DataAiMcp.McpServer/Program.cs). Conditional Access policies (CAC, compliant device, named-locations, MFA) are inherited from the Flank Speed tenant — the MCP server does not need to re-implement them. The dev-mode `Auth:RequireAuthenticatedUser=false` path is explicitly non-production and documented as such in [src/DataAiMcp.McpServer/Auth/CallerSecurityContext.cs](../src/DataAiMcp.McpServer/Auth/CallerSecurityContext.cs).
- **Least privilege** — user-assigned managed identities for App Service, Functions, and Data Factory; RBAC on every data plane in [infra/modules/roleassignments/main.tf](../infra/modules/roleassignments/main.tf); MCP-level policies (`ReadDocuments`, `QueryStructured`, `AdminTools`); per-document ACL trimming via `securityIds` filters in [src/DataAiMcp.McpServer/Rag/RagOrchestrator.cs](../src/DataAiMcp.McpServer/Rag/RagOrchestrator.cs); `shared_access_key_enabled = false` and `default_to_oauth_authentication = true` on Storage; no static credentials, connection strings, or shared keys anywhere in the deployed stack.
- **Assume breach** — TLS 1.2 minimum, HTTPS-only across every service; opt-in customer-managed keys end-to-end via `enable_cmk` ([infra/modules/cmk/main.tf](../infra/modules/cmk/main.tf)) with `infrastructure_encryption_enabled = true` on Storage; OpenTelemetry traces from the MCP server, Application Insights and Log Analytics on every hop, ready for ship-to-SIEM diagnostic settings.

Controls deferred to the operator are **intra-boundary defense-in-depth**, not boundary controls. None of them are required to authenticate a Flank Speed user against the deployed `/mcp`; they are layered hardening an ISSM may require depending on the workload's RMF posture:

- Private Endpoints on PaaS data planes (Storage, Key Vault, AI Search, Foundry, Document Intelligence, Synapse).
- VNet integration on App Service and Functions (requires P1v3+).
- `defaultAction: 'Deny'` on Storage and Key Vault network ACLs.
- `X-Azure-FDID` header pinning on App Service when fronted by Front Door.
- Microsoft Graph `getMemberObjects` fallback for users in groups-overage state (currently logged as a warning in [src/DataAiMcp.McpServer/Auth/CallerSecurityContext.cs](../src/DataAiMcp.McpServer/Auth/CallerSecurityContext.cs)).

In other words: the Zero Trust *boundary* is the Flank Speed tenant; the Zero Trust *controls inside it* are this codebase; the Zero Trust *segmentation inside the boundary* is the operator's call.

## Cost shape

Default SKUs (`B1` App Service Plan, `standard` AI Search, Flex-Consumption Functions, serverless Synapse, pay-as-you-go Foundry) target a low-cost evaluation footprint suitable for a single federal agency department POC. Every SKU is a Bicep parameter — scale up for an agency-wide production deployment by overriding `AZURE_APP_SERVICE_PLAN_SKU`, `AZURE_SEARCH_SKU`, and the Foundry deployment names.

The largest variable cost is Foundry token consumption: embeddings paid once per document chunk during ingestion, and chat completions paid per user question during `query_structured_data`. Both are bounded and observable through App Insights — you can set alerts before any team's usage runs away.

## What's next

- **Walk the decisions list** — work through [Decisions you need to make before `terraform apply`](#decisions-you-need-to-make-before-azd-up) with the federal agency's IT, ISSM, and data owners *before* provisioning anything. Most of these decisions are cheap to get right up front and expensive to change later.
- **Stand it up in Azure Government** — follow the step-by-step deployment guide in the root [README.md](../README.md), substituting the `.us` sovereign-cloud endpoints called out in the [Pitfalls](#pitfalls--read-this-section-twice) section.
- **Plug in the warfare center's data** — point the Flank Speed SharePoint / OneDrive / Dataverse / SQL MI connectors at the specific sites and tables an owning department has authorized in writing. Start with one library and one table; add more incrementally.
- **Connect a client** — register `https://<your-app>.azurewebsites.us/mcp` (or your Private Endpoint hostname) in the MCP client the federal agency has approved. CAC-backed Entra sign-in via Flank Speed flows automatically.
- **Extend it** — add MCP tools for warfare-center-specific systems (CMMS / 3M lookups, NSN search, ISEA work-package search, distance-support case lookup), additional Synapse views, or new ingestion sources. The seams are deliberate.
- **Validate the Gov-cloud configuration end-to-end** — once deployed, confirm Graph calls hit `graph.microsoft.us`, Entra tokens come from `login.microsoftonline.us`, Foundry deployments exist in your chosen Gov region, and your dev workstations can actually reach the Gov endpoints from the federal agency network.

This is a starting point, not a black box. Every Bicep module, ingestion pipeline, and MCP tool is yours to read, fork, and adapt to the federal agency's specific mission.

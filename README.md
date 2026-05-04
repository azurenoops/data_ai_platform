# Data + AI + MCP Platform — NSWC Port Hueneme Division

> A turnkey, **Flank Speed**-aligned reference platform that unifies the documents and structured engineering data scattered across **Naval Surface Warfare Center, Port Hueneme Division (NSWC PHD)** behind a single secure **Model Context Protocol (MCP)** endpoint — so any approved AI client can answer grounded, cited questions about combat-system in-service engineering, lifecycle logistics, fleet readiness, and technical guidance.

---

## What this is

A single, governed Azure platform that lets NSWC PHD staff and their AI assistants ask questions across the warfare center's data — and get back grounded answers with citations — without each department, program office, or contractor team standing up a one-off "AI on my data" project.

It's built on Microsoft technology that **already** lives inside the warfare center's tenant: **Flank Speed** (M365 GCC High), **Azure Government**, **Microsoft 365 Copilot–compatible MCP**, and **Microsoft AI Foundry**. There is nothing custom about the stack — only how it is wired together for NSWC PHD's mission.

It is delivered as **infrastructure-as-code** ([infra/](infra)) plus a small, focused **.NET 9 codebase** ([src/](src)) that:

- **Ingests** documents and tabular data from the systems NSWC PHD already operates — Flank Speed SharePoint and OneDrive, Azure SQL Managed Instance, Dataverse, Azure Files / ADLS.
- **Curates and indexes** them in-tenant — text into Azure AI Search, structured tables into Synapse serverless SQL views over Parquet.
- **Exposes** the unified corpus through one Entra-protected MCP endpoint that any compliant AI client can call.

You run `terraform apply` once, against an authorized Azure Government subscription, and you get a production-shaped data + AI + MCP stack inside the warfare center's own boundary.

---

## Why it exists

Today, the systems that hold NSWC PHD's most valuable engineering knowledge — technical manuals, ISEA work packages, OPNAV / SECNAV / NAVSEA instructions, SHIPALTs and OrdAlts, ECPs, PMS feedback, CASREPs, ILS records, distance-support cases, range and test data — are spread across **separate** SharePoint libraries, drives, databases, and file shares.

**None of that data is currently reachable through an AI surface.** Every cross-system question is answered the same way: a person opens SharePoint, opens a SQL client, opens Dataverse, opens a file share, and stitches the answer together by hand. Engineers and analysts spend hours on lookups that the data already supports, the same questions get researched repeatedly across departments, and there is no governed, reusable path for any future copilot or AI assistant the command's leadership might want to stand up.

That gap is exactly what the **CDAO**, **Task Force Lima**, and **DON CIO AI guidance** call out: don't let every team build its own bespoke AI-on-our-data stack. Build one governed platform. Reuse it.

This repository is that platform, scoped to NSWC PHD's mission.

---

## How it helps

| For… | What changes |
| --- | --- |
| **Combat-systems engineers** | Ask one question and get cited answers spanning the technical manual *and* the latest open CASREPs against that equipment — without opening four different systems. |
| **In-Service Engineering Agents (ISEAs)** | Surface the right ISEA work package, the parent OPNAV instruction, and the related ECPs from a single natural-language prompt. |
| **Logistics & supply analysts** | Run NL → T-SQL queries against curated 3M / PMS / ILS data and see the generated SQL alongside the rows — every answer is auditable. |
| **Distance-support analysts** | Pull case-tracking context and engineering documentation in one turn for fleet inquiries. |
| **NSWC PHD IT / N6 / ISSM** | Authorize the AI surface area **once** and let multiple departments and program offices consume it — instead of reviewing one bespoke RAG app per team. |
| **Program offices & contractors** | Build copilots against a sanctioned, governed endpoint — no need to stand up indexing, embedding, search, or auth from scratch. |
| **Architects & solution engineers** | Use a working reference for MCP as the integration contract for an internal AI surface, including the migration path to Azure Government for higher impact levels. |

Every answer is **grounded with citations** (hybrid BM25 + vector + semantic-rerank search in Azure AI Search). Every hop is **identity-bound** (managed identities, RBAC, JWT). Every byte stays inside the warfare center's Azure boundary.

---

## What it can do today

Once deployed, NSWC PHD staff (or their AI clients) can ask questions like:

- *"Summarize the latest safety bulletin for the combat system I'm working on and link to the source."*
- *"Show me open Priority-1 CASREPs against the systems this division is the ISEA for, in the last 30 days."*
- *"For ships in availability supported by NSWC PHD this quarter, list the open ECPs and any associated ISEA technical guidance."*
- *"What does OPNAVINST 5100.19 say about confined-space entry, and which warfare-center SOPs reference it?"*
- *"What sources are connected, and what fields are available on `nswc_phd_casreps`?"*

The platform answers them through five MCP tools:

| Tool | Purpose |
| --- | --- |
| `search_documents` | Hybrid search over the unified document corpus (instructions, technical manuals, ISEA work packages, SOPs, bulletins). |
| `get_document` | Retrieve all chunks of a single document in order — the full ISEA work package, not just the top hit. |
| `query_structured_data` | NL → T-SQL over Synapse serverless views (CASREPs, 3M / PMS, ILS, supply); returns rows **and** the generated SQL. |
| `describe_dataset` | Self-describing catalog of available tables. |
| `list_sources` | Self-describing catalog of connected systems. |

New tools are a **class drop-in**. New data sources are an **ADF copy activity** or a **blob upload** to the `landing/` container. The seams are deliberate.

See the architecture and data-flow diagram in [docs/README.md](docs/README.md#how-a-request-flows).

---

## Where it runs

This reference architecture is intended to deploy into the warfare center's existing cloud footprint:

- **Tenant** — Flank Speed (the DON's Microsoft 365 GCC High tenant).
- **Cloud** — Azure Government (`usgovvirginia` or `usgovarizona`).
- **Classification** — IL4 / IL5 unclassified CUI workloads. SIPR / JWICS classified work is out of scope.
- **Identity** — Entra ID via Flank Speed; CAC-backed sign-in via the user's existing tenant credentials; no shared secrets.
- **Network** — public ingress by default for evaluation; production deployments should sit behind Private Endpoints + Front Door / App Gateway.

The Terraform is region-agnostic and deploys into commercial Azure too — the same `terraform apply` invocation works in either cloud, given an appropriately scoped subscription. For Gov, a small set of sovereign-cloud configuration changes is required (`login.microsoftonline.us`, `graph.microsoft.us`, App Service hostname `.azurewebsites.us`, and `provider "azurerm" { environment = "usgovernment" }`). The full retargeting procedure is documented in [docs/DEPLOYMENT.md §5](docs/DEPLOYMENT.md#5-sovereign-cloud-code-adjustments) and [§15.4](docs/DEPLOYMENT.md#154-patch-the-workflows-for-gov-cloud).

---

## How it's governed

**Zero Trust posture.** The Flank Speed / Azure Government tenant defines the network and identity boundary; this codebase implements Zero Trust *inside* that boundary. Every `/mcp` call is explicitly verified against a Flank Speed-issued Entra JWT, every service-to-service hop runs on a least-privileged user-assigned managed identity, and every byte at rest is encrypted — with opt-in customer-managed keys end-to-end. Conditional Access (CAC, compliant device, location), MFA, and device compliance are inherited from Flank Speed. Private Endpoints, VNet integration, and `defaultAction: 'Deny'` on data-plane network ACLs are intra-boundary defense-in-depth that operators layer on per their ISSM's network-control requirements — not prerequisites for the Zero Trust posture in this context.

Built on the controls a Navy ATO will examine:

- **Identity** — Entra ID with JWT validation on `/mcp`; user-assigned managed identities for App Service, Functions, and Data Factory; no static credentials anywhere.
- **Authorization** — RBAC on every Azure data plane (Storage, AI Search, Foundry, Document Intelligence, Synapse, Key Vault). MCP-level policies (`ReadDocuments`, `QueryStructured`, `AdminTools`). Per-document ACL trimming on the search index via `securityIds`.
- **Encryption** — TLS in transit; Microsoft-managed keys at rest by default; opt-in **customer-managed keys** via Key Vault.
- **Auditing** — Application Insights + Log Analytics on every service; OpenTelemetry traces; tool calls observable end-to-end.
- **Data residency** — every byte stays in the chosen Azure region. Multi-region DR is opt-in.

The full posture, decisions, and pitfalls are documented in [docs/README.md](docs/README.md).

---

## Documentation

| Document | Audience | Purpose |
| --- | --- | --- |
| [docs/README.md](docs/README.md) | NSWC PHD leadership, IT, ISSM/ISSO, data owners, architects | What the platform is, the problem it solves at the warfare center, decisions that must be made before deploy, and the pitfalls to avoid in Flank Speed / Azure Government. |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Cloud / DevOps engineers running the deployment | Comprehensive step-by-step deployment guide — prerequisites, pre-flight checklist, sovereign-cloud retargeting, Terraform workflow (`bootstrap` → `init` → `apply`), zip-deploy of the apps, manual post-provision steps, troubleshooting, tear-down, RBAC + Graph permissions appendices, signoff checklist. |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Engineers extending or enhancing the platform | How to add MCP tools, ingestion sources, datasets; how to evolve the search index; how to change models, run locally, write tests, ship through CI/CD; coding standards and Definition of Done. |
| [docs/INGESTION.md](docs/INGESTION.md) + [docs/ingestion/](docs/ingestion/) | Operators onboarding data sources; developers adding source types; SREs investigating ingestion failures | Hub + per-source cookbooks for SharePoint, OneDrive, Azure File Share, SQL MI, SharePoint Lists, Dataverse, manual blob drop; secret-rotation runbook; "adding a source type" cookbook. |

### Source-tree quick links

| Area | Location |
| --- | --- |
| MCP server (ASP.NET Core, JWT-protected `/mcp`) | [src/DataAiMcp.McpServer/](src/DataAiMcp.McpServer) |
| MCP tools (search, structured, metadata) | [src/DataAiMcp.McpServer/Tools/](src/DataAiMcp.McpServer/Tools) |
| RAG orchestrator (hybrid + semantic rerank) | [src/DataAiMcp.McpServer/Rag/RagOrchestrator.cs](src/DataAiMcp.McpServer/Rag/RagOrchestrator.cs) |
| NL → T-SQL generator | [src/DataAiMcp.McpServer/Synapse/SqlGenerator.cs](src/DataAiMcp.McpServer/Synapse/SqlGenerator.cs) |
| Ingestion Functions (blob trigger, SharePoint, OneDrive) | [src/DataAiMcp.Ingestion.Functions/](src/DataAiMcp.Ingestion.Functions) |
| Document pipeline (DocIntel → chunk → embed → index) | [src/DataAiMcp.Ingestion.Functions/Pipeline/DocumentIngestionPipeline.cs](src/DataAiMcp.Ingestion.Functions/Pipeline/DocumentIngestionPipeline.cs) |
| Shared library (auth, AI clients, schema, telemetry) | [src/DataAiMcp.Shared/](src/DataAiMcp.Shared) |
| Search index schema | [src/DataAiMcp.Shared/Search/SearchIndexSchema.cs](src/DataAiMcp.Shared/Search/SearchIndexSchema.cs) |
| Index provisioner (idempotent) | [src/DataAiMcp.Tools.IndexProvisioner/](src/DataAiMcp.Tools.IndexProvisioner) |
| Sample MCP client | [src/Samples/DataAiMcp.SampleClient.Console/](src/Samples/DataAiMcp.SampleClient.Console) |
| Terraform entry point | [infra/main.tf](infra/main.tf) + [infra/primary.tf](infra/primary.tf) |
| Terraform modules | [infra/modules/](infra/modules) (15 modules) |
| Terraform per-environment vars | [infra/envs/](infra/envs) |
| Terraform remote state bootstrap | [infra/bootstrap/](infra/bootstrap) |
| Synapse view DDL | [infra/synapse/views/](infra/synapse/views) |
| Data Factory pipeline JSON | [infra/datafactory/pipelines/](infra/datafactory/pipelines) |
| Post-provision / post-deploy hooks | [infra/scripts/](infra/scripts) |
| GitHub Actions — Terraform plan/apply | [.github/workflows/terraform.yml](.github/workflows/terraform.yml) |
| GitHub Actions — app zip deploy | [.github/workflows/cd.yml](.github/workflows/cd.yml) |
| Test projects | [tests/](tests) |

---

## Reference & policy

- [Department of Defense Chief Digital and Artificial Intelligence Office (CDAO)](https://www.ai.mil/)
- [Task Force Lima — DoD Generative AI Task Force](https://www.defense.gov/News/Releases/Release/Article/3489803/dod-announces-establishment-of-generative-ai-task-force/)
- [DON CIO — AI guidance and policy resources](https://www.doncio.navy.mil/)
- [Naval Surface Warfare Center, Port Hueneme Division](https://www.navsea.navy.mil/Home/Warfare-Centers/NSWC-Port-Hueneme/)
- [Microsoft Azure Government documentation](https://learn.microsoft.com/azure/azure-government/)
- [Microsoft 365 GCC High (Flank Speed) overview](https://learn.microsoft.com/microsoft-365/enterprise/microsoft-365-gcchigh-mapping)
- [Microsoft AI Foundry documentation](https://learn.microsoft.com/azure/ai-foundry/)
- [Model Context Protocol (MCP) specification](https://modelcontextprotocol.io/)

---

## At a glance

- **Platform:** .NET 9 + ASP.NET Core, Azure Functions (Flex Consumption), Azure AI Search, Azure AI Foundry, Azure Document Intelligence, Synapse Serverless, ADLS Gen2, Azure Data Factory.
- **IaC:** Terraform (15 modules under `infra/modules/`, providers: `azurerm`, `azapi`, `random`); state in Azure Storage; deploy via GitHub Actions OIDC.
- **Auth:** Entra ID JWT, user-assigned managed identities, RBAC.
- **Surface:** One MCP HTTP endpoint with five tools today; designed for class-drop-in extension.
- **Status:** Reference implementation. Authorization-package artifacts are scaffolded; the ATO and operational signoff are the operator's responsibility.

For deployment, start at [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md). For development, start at [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). For the value story and the decisions that have to be made before either, start at [docs/README.md](docs/README.md).

locals {
  # Built-in role definition IDs - lifted verbatim from the Bicep module.
  roles = {
    storage_blob_data_contributor            = "ba92f5b4-2d11-453d-a403-e96b0029c9fe"
    storage_blob_data_reader                 = "2a2b9908-6ea1-4ae2-8e65-a410df84e7d1"
    search_service_contributor               = "7ca78c08-252a-4471-8644-bb5ff32d4ba0"
    search_index_data_contributor            = "8ebe5a00-799e-43f5-93ac-243d3dce84a7"
    search_index_data_reader                 = "1407120a-92aa-4202-b7e9-c0e197c71c8f"
    cognitive_services_user                  = "a97b65f3-24c7-4388-baec-2e87135dc908"
    cognitive_services_openai_user           = "5e0bd9bd-7b93-4f28-af87-19fc36ad61bd"
    cognitive_services_contributor           = "25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68"
    key_vault_secrets_user                   = "4633458b-17de-408a-b874-0445c86b69e6"
    key_vault_crypto_service_encryption_user = "e147488a-f6f5-4113-8e2d-b22465e65bf6"
  }

  has_dev = var.dev_principal_id != ""
}

data "azurerm_subscription" "current" {}

# ---- MCP server: read storage + Search index, invoke Foundry chat/embeddings ----
resource "azurerm_role_assignment" "mcp_storage_reader" {
  scope              = var.storage_account_id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${local.roles.storage_blob_data_reader}"
  principal_id       = var.mcp_server_principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "mcp_search_reader" {
  scope              = var.search_id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${local.roles.search_index_data_reader}"
  principal_id       = var.mcp_server_principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "mcp_foundry_user" {
  scope              = var.foundry_account_id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${local.roles.cognitive_services_openai_user}"
  principal_id       = var.mcp_server_principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "mcp_kv_secrets_user" {
  scope              = var.key_vault_id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${local.roles.key_vault_secrets_user}"
  principal_id       = var.mcp_server_principal_id
  principal_type     = "ServicePrincipal"
}

# ---- Ingestion: write storage, write Search index, invoke DI + embeddings ----
resource "azurerm_role_assignment" "ing_storage_writer" {
  scope              = var.storage_account_id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${local.roles.storage_blob_data_contributor}"
  principal_id       = var.ingestion_principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "ing_search_contributor" {
  scope              = var.search_id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${local.roles.search_index_data_contributor}"
  principal_id       = var.ingestion_principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "ing_search_service" {
  scope              = var.search_id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${local.roles.search_service_contributor}"
  principal_id       = var.ingestion_principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "ing_doc_intel_user" {
  scope              = var.document_intelligence_account_id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${local.roles.cognitive_services_user}"
  principal_id       = var.ingestion_principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "ing_foundry_embeddings" {
  scope              = var.foundry_account_id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${local.roles.cognitive_services_openai_user}"
  principal_id       = var.ingestion_principal_id
  principal_type     = "ServicePrincipal"
}

# ---- Data Factory: write to ADLS curated/raw ----
resource "azurerm_role_assignment" "adf_storage_writer" {
  scope              = var.storage_account_id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${local.roles.storage_blob_data_contributor}"
  principal_id       = var.data_factory_principal_id
  principal_type     = "ServicePrincipal"
}

# Data Factory MI reads operator-managed secrets (AFS storage key, SharePoint
# AAD app-reg client secret) from KV at pipeline runtime when ADF pipelines
# are enabled. Gated so the role is not granted in unused environments.
resource "azurerm_role_assignment" "adf_kv_secrets_user" {
  count = var.enable_data_factory_pipelines ? 1 : 0

  scope              = var.key_vault_id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${local.roles.key_vault_secrets_user}"
  principal_id       = var.data_factory_principal_id
  principal_type     = "ServicePrincipal"
}

# ---- Developer / CI principal: full local-dev access (skipped if empty) ----
resource "azurerm_role_assignment" "dev_storage" {
  count              = local.has_dev ? 1 : 0
  scope              = var.storage_account_id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${local.roles.storage_blob_data_contributor}"
  principal_id       = var.dev_principal_id
  principal_type     = "User"
}

resource "azurerm_role_assignment" "dev_search" {
  count              = local.has_dev ? 1 : 0
  scope              = var.search_id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${local.roles.search_service_contributor}"
  principal_id       = var.dev_principal_id
  principal_type     = "User"
}

resource "azurerm_role_assignment" "dev_search_data" {
  count              = local.has_dev ? 1 : 0
  scope              = var.search_id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${local.roles.search_index_data_contributor}"
  principal_id       = var.dev_principal_id
  principal_type     = "User"
}

resource "azurerm_role_assignment" "dev_foundry" {
  count              = local.has_dev ? 1 : 0
  scope              = var.foundry_account_id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${local.roles.cognitive_services_openai_user}"
  principal_id       = var.dev_principal_id
  principal_type     = "User"
}

resource "azurerm_role_assignment" "dev_kv" {
  count              = local.has_dev ? 1 : 0
  scope              = var.key_vault_id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${local.roles.key_vault_secrets_user}"
  principal_id       = var.dev_principal_id
  principal_type     = "User"
}

# ---- CMK consumers: KV Crypto Service Encryption User on the vault ----
resource "azurerm_role_assignment" "cmk_consumer_kv_access" {
  for_each = toset([for pid in var.cmk_consumer_principal_ids : pid if pid != ""])

  scope              = var.key_vault_id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${local.roles.key_vault_crypto_service_encryption_user}"
  principal_id       = each.value
  principal_type     = "ServicePrincipal"
}

data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

data "azurerm_storage_account" "datalake" {
  name                = element(split("/", var.storage_account_id), length(split("/", var.storage_account_id)) - 1)
  resource_group_name = element(split("/", var.storage_account_id), 4)
}

locals {
  cmk_enabled   = var.cmk_key_uri != "" && var.cmk_user_assigned_identity_id != ""
  cmk_key_name  = local.cmk_enabled ? element(split("/", var.cmk_key_uri), length(split("/", var.cmk_key_uri)) - 1) : ""
  cmk_vault_uri = local.cmk_enabled ? "${trimsuffix(var.cmk_key_uri, "/keys/${local.cmk_key_name}")}/" : ""

  search_name  = element(split("/", var.search_account_id), length(split("/", var.search_account_id)) - 1)
  storage_name = data.azurerm_storage_account.datalake.name
  dfs_endpoint = data.azurerm_storage_account.datalake.primary_dfs_endpoint

  identity_block = local.cmk_enabled ? {
    type = "SystemAssigned,UserAssigned"
    userAssignedIdentities = {
      (var.cmk_user_assigned_identity_id) = {}
    }
    } : {
    type = "SystemAssigned"
  }

  encryption_block = local.cmk_enabled ? {
    keySource = "Microsoft.KeyVault"
    keyVaultProperties = {
      keyName          = local.cmk_key_name
      keyVaultUri      = local.cmk_vault_uri
      identityClientId = var.cmk_user_assigned_identity_client_id
    }
  } : null

  account_properties = merge(
    {
      customSubDomainName    = var.account_name
      publicNetworkAccess    = "Enabled"
      disableLocalAuth       = true
      allowProjectManagement = true
      networkAcls = {
        defaultAction       = "Allow"
        virtualNetworkRules = []
        ipRules             = []
      }
    },
    local.cmk_enabled ? { encryption = local.encryption_block } : {},
  )
}

resource "azapi_resource" "account" {
  type      = "Microsoft.CognitiveServices/accounts@2025-04-01-preview"
  name      = var.account_name
  parent_id = data.azurerm_resource_group.this.id
  location  = var.location
  tags      = var.tags

  body = {
    kind = "AIServices"
    sku = {
      name = "S0"
    }
    identity   = local.identity_block
    properties = local.account_properties
  }

  response_export_values = ["identity.principalId", "properties.endpoint"]
}

resource "azapi_resource" "project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview"
  name      = var.project_name
  parent_id = azapi_resource.account.id
  location  = var.location
  tags      = var.tags

  body = {
    identity = {
      type = "SystemAssigned"
    }
    properties = {
      displayName = var.project_name
      description = "Foundry project for the Data + AI + MCP platform."
    }
  }

  response_export_values = ["identity.principalId"]
}

resource "azapi_resource" "search_connection" {
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "aisearch"
  parent_id = azapi_resource.project.id

  body = {
    properties = {
      category      = "CognitiveSearch"
      target        = "https://${local.search_name}.search.windows.net"
      authType      = "AAD"
      isSharedToAll = true
      metadata = {
        ApiType    = "Azure"
        ResourceId = var.search_account_id
      }
    }
  }
}

resource "azapi_resource" "storage_connection" {
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "datalake"
  parent_id = azapi_resource.project.id

  body = {
    properties = {
      category      = "AzureStorageAccount"
      target        = local.dfs_endpoint
      authType      = "AAD"
      isSharedToAll = true
      metadata = {
        ApiType    = "Azure"
        ResourceId = var.storage_account_id
      }
    }
  }
}

# Sequential deployment chain replaces Bicep's @batchSize(1) - parallel creates against the
# same Foundry account often fail with quota errors. Chain order: chat -> chatMini -> embedding.
resource "azapi_resource" "deployment_chat" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2024-10-01"
  name      = var.chat_deployment
  parent_id = azapi_resource.account.id

  body = {
    sku = {
      name     = "GlobalStandard"
      capacity = 30
    }
    properties = {
      model = {
        format  = "OpenAI"
        name    = "gpt-4o"
        version = "2024-11-20"
      }
      raiPolicyName = "Microsoft.DefaultV2"
    }
  }
}

resource "azapi_resource" "deployment_chat_mini" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2024-10-01"
  name      = var.chat_mini_deployment
  parent_id = azapi_resource.account.id

  body = {
    sku = {
      name     = "GlobalStandard"
      capacity = 30
    }
    properties = {
      model = {
        format  = "OpenAI"
        name    = "gpt-4o-mini"
        version = "2024-07-18"
      }
      raiPolicyName = "Microsoft.DefaultV2"
    }
  }

  depends_on = [azapi_resource.deployment_chat]
}

resource "azapi_resource" "deployment_embedding" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2024-10-01"
  name      = var.embedding_deployment
  parent_id = azapi_resource.account.id

  body = {
    sku = {
      name     = "Standard"
      capacity = 30
    }
    properties = {
      model = {
        format  = "OpenAI"
        name    = "text-embedding-3-large"
        version = "1"
      }
      raiPolicyName = "Microsoft.DefaultV2"
    }
  }

  depends_on = [azapi_resource.deployment_chat_mini]
}

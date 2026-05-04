terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.18"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
  storage_use_azuread = true
}

variable "environment_name" {
  description = "Logical environment name (e.g. dev, prod). Used as a suffix for the state RG and a salt for the storage account name."
  type        = string
}

variable "location" {
  description = "Region to create the state storage in."
  type        = string
  default     = "eastus2"
}

variable "ci_principal_id" {
  description = "Object ID of the CI service principal that needs Storage Blob Data Contributor on the state container. Empty to skip (you'll grant access manually later)."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to every bootstrap resource."
  type        = map(string)
  default     = {}
}

data "azurerm_subscription" "current" {}

locals {
  state_token   = lower(substr(sha1("${data.azurerm_subscription.current.subscription_id}-tfstate-${var.environment_name}"), 0, 13))
  state_rg_name = "rg-tfstate-${var.environment_name}"
  state_sa_name = substr(replace("sttfstate${local.state_token}", "-", ""), 0, 24)
  tags = merge(
    { "purpose" = "terraform-state", "environment" = var.environment_name },
    var.tags,
  )
}

resource "azurerm_resource_group" "state" {
  name     = local.state_rg_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "state" {
  name                              = local.state_sa_name
  resource_group_name               = azurerm_resource_group.state.name
  location                          = azurerm_resource_group.state.location
  account_tier                      = "Standard"
  account_replication_type          = "ZRS"
  account_kind                      = "StorageV2"
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  infrastructure_encryption_enabled = true

  blob_properties {
    versioning_enabled       = true
    change_feed_enabled      = false
    last_access_time_enabled = false

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

# Grant the CI principal Storage Blob Data Contributor on the state account so it can read/write state.
data "azurerm_role_definition" "blob_data_contributor" {
  name = "Storage Blob Data Contributor"
}

resource "azurerm_role_assignment" "ci_state_writer" {
  count              = var.ci_principal_id == "" ? 0 : 1
  scope              = azurerm_storage_account.state.id
  role_definition_id = data.azurerm_role_definition.blob_data_contributor.id
  principal_id       = var.ci_principal_id
}

output "state_resource_group_name" {
  description = "Pass to `terraform init -backend-config=resource_group_name=...`"
  value       = azurerm_resource_group.state.name
}

output "state_storage_account_name" {
  description = "Pass to `terraform init -backend-config=storage_account_name=...`"
  value       = azurerm_storage_account.state.name
}

output "state_container_name" {
  description = "Pass to `terraform init -backend-config=container_name=...`"
  value       = azurerm_storage_container.tfstate.name
}

output "init_backend_config_snippet" {
  description = "Copy/paste these flags onto a `terraform init` command."
  value = format(
    "-backend-config=\"resource_group_name=%s\" -backend-config=\"storage_account_name=%s\" -backend-config=\"container_name=%s\" -backend-config=\"key=data-ai-mcp.tfstate\"",
    azurerm_resource_group.state.name,
    azurerm_storage_account.state.name,
    azurerm_storage_container.tfstate.name,
  )
}

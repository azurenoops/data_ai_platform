provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  storage_use_azuread = true
}

provider "azapi" {
  # Inherits credentials from azurerm provider chain (env / OIDC / az CLI).
}

data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

# ---- Primary resource group ----
resource "azurerm_resource_group" "primary" {
  name     = "rg-${var.environment_name}"
  location = var.location
  tags     = local.tags
}

# ---- Secondary resource group (DR only) ----
resource "azurerm_resource_group" "dr" {
  count    = local.enable_dr ? 1 : 0
  name     = "rg-${var.environment_name}-dr"
  location = var.secondary_location
  tags     = local.tags
}

locals {
  base_app_settings = {
    APPLICATIONINSIGHTS_CONNECTION_STRING = var.app_insights_connection_string
    ASPNETCORE_ENVIRONMENT                = "Production"
    WEBSITE_RUN_FROM_PACKAGE              = "1"
  }

  merged_app_settings = merge(local.base_app_settings, var.app_settings)
}

resource "azurerm_service_plan" "this" {
  name                = var.plan_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  os_type  = "Linux"
  sku_name = var.sku
}

resource "azurerm_linux_web_app" "this" {
  name                = var.site_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
  service_plan_id     = azurerm_service_plan.this.id

  https_only                      = true
  key_vault_reference_identity_id = var.user_assigned_identity_id

  identity {
    type         = "UserAssigned"
    identity_ids = [var.user_assigned_identity_id]
  }

  site_config {
    always_on           = var.sku != "F1"
    ftps_state          = "Disabled"
    http2_enabled       = true
    minimum_tls_version = "1.2"
    use_32_bit_worker   = false

    application_stack {
      dotnet_version = "9.0"
    }
  }

  app_settings = local.merged_app_settings
}

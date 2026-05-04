resource "azurerm_log_analytics_workspace" "this" {
  name                = var.log_analytics_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  sku                          = "PerGB2018"
  retention_in_days            = 30
  local_authentication_enabled = true
  internet_ingestion_enabled   = true
  internet_query_enabled       = true
}

resource "azurerm_application_insights" "this" {
  name                          = var.app_insights_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  tags                          = var.tags
  application_type              = "web"
  workspace_id                  = azurerm_log_analytics_workspace.this.id
  local_authentication_disabled = true
  internet_ingestion_enabled    = true
  internet_query_enabled        = true
}

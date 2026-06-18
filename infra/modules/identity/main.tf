resource "azurerm_user_assigned_identity" "mcp_server" {
  name                = var.mcp_server_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "ingestion" {
  name                = var.ingestion_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "data_factory" {
  name                = var.data_factory_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "portal" {
  name                = var.portal_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

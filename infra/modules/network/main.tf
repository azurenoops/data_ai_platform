terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.18.0, < 4.71.0"
    }
  }
}

resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.vnet_address_space
  tags                = var.tags
}

# App Service plan VNet integration subnet (MCP server egress through VNet).
resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_app_address_prefix]

  delegation {
    name = "appservice-delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Function App plan VNet integration subnet (ingestion functions egress through VNet).
resource "azurerm_subnet" "functions" {
  name                 = "snet-functions"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_functions_address_prefix]

  delegation {
    name = "appservice-delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Private endpoint subnet (NIC IPs land here). Must have PE network policies disabled.
resource "azurerm_subnet" "pe" {
  name                              = "snet-pe"
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [var.subnet_pe_address_prefix]
  private_endpoint_network_policies = "Disabled"
}

# Private DNS zones (one per service token in var.private_dns_zone_names).
resource "azurerm_private_dns_zone" "zones" {
  for_each            = var.private_dns_zone_names
  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Link every zone to the VNet so DNS resolution works for resources in the VNet.
resource "azurerm_private_dns_zone_virtual_network_link" "links" {
  for_each              = var.private_dns_zone_names
  name                  = "${each.key}-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.zones[each.key].name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}

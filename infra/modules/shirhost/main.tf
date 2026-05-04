# ---------------------------------------------------------------------------
# Self-Hosted Integration Runtime host VM (opt-in).
#
# Provisions a hardened Windows Server 2022 VM into an existing
# operator-supplied subnet (var.subnet_id). Trusted Launch + system-assigned
# identity + AzureMonitor agent. Local admin password is auto-generated and
# stored in Key Vault as `shir-host-admin-password`.
#
# SHIR shim install method is configurable:
#   - DSC (default): idempotent, reboot-handling, self-heals on auth-key
#     rotation. Compiled MOF + module dependencies are uploaded as a versioned
#     blob (via SHA256) into the existing `deploy/` filesystem, fetched by the
#     VM's system-assigned identity (no SAS).
#   - CustomScript (fallback): retained for sovereign-cloud egress profiles
#     where DSC pull from `wpr.azure.com` is unreliable.
#
# Domain join, AD service-account provisioning, and Bastion are out of scope
# for this module.
# ---------------------------------------------------------------------------

locals {
  use_dsc           = var.shir_install_method == "DSC"
  use_custom_script = var.shir_install_method == "CustomScript"

  dsc_blob_path = "dsc/shir/InstallShir.zip"
}

# ---- NIC + NSG (RDP from bastion subnet only) ------------------------------

resource "azurerm_network_security_group" "this" {
  name                = "${var.vm_name}-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "AllowRDPFromBastion"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.bastion_subnet_address_prefix
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "this" {
  name                = "${var.vm_name}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_security_group_association" "this" {
  network_interface_id      = azurerm_network_interface.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}

# ---- Local admin password ---------------------------------------------------

resource "random_password" "admin" {
  length  = 32
  special = true
  keepers = {
    vm = var.vm_name
  }
}

resource "azurerm_key_vault_secret" "shir_admin_password" {
  name         = "shir-host-admin-password"
  value        = random_password.admin.result
  key_vault_id = var.key_vault_id
  content_type = "SHIR host local admin password"

  expiration_date = timeadd(timestamp(), "8760h") # +1 year

  lifecycle {
    ignore_changes = [expiration_date]
  }
}

# ---- Windows Server 2022 with Trusted Launch -------------------------------

resource "azurerm_windows_virtual_machine" "this" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  size                  = var.vm_size
  admin_username        = var.vm_admin_username
  admin_password        = random_password.admin.result
  network_interface_ids = [azurerm_network_interface.this.id]

  secure_boot_enabled = true
  vtpm_enabled        = true

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
}

# ---- DSC blob upload (only when install method is DSC) ---------------------

resource "azurerm_storage_blob" "shir_dsc_zip" {
  count = local.use_dsc ? 1 : 0

  name                   = local.dsc_blob_path
  storage_account_name   = var.storage_account_name
  storage_container_name = var.dsc_blob_container
  type                   = "Block"
  source                 = var.dsc_zip_path
  content_type           = "application/zip"
}

# Grant the VM's system-assigned identity Storage Blob Data Reader so the DSC
# extension can fetch the ZIP via MI (no SAS).
resource "azurerm_role_assignment" "shir_host_dsc_reader" {
  count = local.use_dsc ? 1 : 0

  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_windows_virtual_machine.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# ---- DSC extension (default install method) --------------------------------

resource "azurerm_virtual_machine_extension" "dsc" {
  count = local.use_dsc ? 1 : 0

  name                       = "InstallShir-DSC"
  virtual_machine_id         = azurerm_windows_virtual_machine.this.id
  publisher                  = "Microsoft.Powershell"
  type                       = "DSC"
  type_handler_version       = "2.83"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    ModulesUrl            = azurerm_storage_blob.shir_dsc_zip[0].url
    ConfigurationFunction = "InstallShir.ps1\\InstallShir"
    Properties = {
      InstallerUrl = var.shir_installer_url
    }
  })

  protected_settings = jsonencode({
    Items = {
      ShirAuthorizationKey = var.shir_authorization_key
    }
  })

  depends_on = [
    azurerm_role_assignment.shir_host_dsc_reader,
  ]
}

# ---- Custom Script extension (sovereign-cloud fallback) --------------------

resource "azurerm_virtual_machine_extension" "shir_install_customscript" {
  count = local.use_custom_script ? 1 : 0

  name                 = "InstallShir-CustomScript"
  virtual_machine_id   = azurerm_windows_virtual_machine.this.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    fileUris = [var.shir_installer_url]
  })

  protected_settings = jsonencode({
    commandToExecute = "powershell.exe -ExecutionPolicy Unrestricted -Command \"& '${path.module}\\scripts\\install-shir.ps1' -AuthorizationKey '${var.shir_authorization_key}'\""
  })
}

# ---- AzureMonitor agent (Defender / patch / metric telemetry) --------------

resource "azurerm_virtual_machine_extension" "azure_monitor" {
  name                       = "AzureMonitorWindowsAgent"
  virtual_machine_id         = azurerm_windows_virtual_machine.this.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorWindowsAgent"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
}

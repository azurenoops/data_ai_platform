variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "vm_name" {
  description = "Name of the SHIR host VM."
  type        = string
}

variable "vm_size" {
  description = "Azure VM SKU."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "vm_admin_username" {
  description = "Local administrator username on the VM."
  type        = string
  default     = "shiradmin"
}

variable "subnet_id" {
  description = "Resource ID of an existing subnet to deploy the VM into."
  type        = string
}

variable "bastion_subnet_address_prefix" {
  description = "CIDR allowed inbound RDP into the VM (typically the Azure Bastion subnet)."
  type        = string
}

variable "key_vault_id" {
  description = "Resource ID of the Key Vault that stores the local-admin password secret."
  type        = string
}

variable "storage_account_name" {
  description = "Name of the platform storage account holding the deploy/ filesystem (used for DSC ZIP)."
  type        = string
}

variable "storage_account_id" {
  description = "Resource ID of the platform storage account (used for the Storage Blob Data Reader role assignment)."
  type        = string
}

variable "shir_authorization_key" {
  description = "Primary auth key for the SHIR. Passed to the install scripts as protected settings."
  type        = string
  sensitive   = true
}

variable "shir_installer_url" {
  description = "URL of the Microsoft Integration Runtime MSI installer."
  type        = string
  default     = "https://download.microsoft.com/download/E/4/7/E4771905-1079-445B-8BF9-8A1A075D8A10/IntegrationRuntime_5.x.msi"
}

variable "shir_install_method" {
  description = "How the SHIR shim is installed on the host VM. 'DSC' or 'CustomScript'."
  type        = string
  default     = "DSC"

  validation {
    condition     = contains(["DSC", "CustomScript"], var.shir_install_method)
    error_message = "shir_install_method must be DSC or CustomScript."
  }
}

variable "dsc_blob_container" {
  description = "Name of the storage container that holds the DSC ZIP."
  type        = string
  default     = "deploy"
}

variable "dsc_zip_path" {
  description = "Local filesystem path to the compiled DSC ZIP (built by infra/modules/shirhost/dsc/build-dsc.ps1)."
  type        = string
  default     = ""
}

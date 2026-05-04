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

variable "storage_account_name" {
  type = string
}

variable "containers" {
  description = "Containers / ADLS Gen2 filesystems to create on the account."
  type        = list(string)
  default     = ["landing", "raw", "curated", "chunks"]
}

variable "sku_name" {
  description = "Replication SKU. Use Standard_RAGZRS for cross-region read failover when DR is enabled."
  type        = string
  default     = "Standard_LRS"

  validation {
    condition = contains(
      ["Standard_LRS", "Standard_ZRS", "Standard_GRS", "Standard_RAGRS", "Standard_GZRS", "Standard_RAGZRS"],
      var.sku_name,
    )
    error_message = "sku_name must be one of: Standard_LRS, Standard_ZRS, Standard_GRS, Standard_RAGRS, Standard_GZRS, Standard_RAGZRS."
  }
}

variable "cmk_key_uri" {
  description = "Versionless KV key URL. Empty disables CMK."
  type        = string
  default     = ""
}

variable "cmk_user_assigned_identity_id" {
  description = "UAMI resource ID used to wrap/unwrap CMK. Required when cmk_key_uri is set."
  type        = string
  default     = ""
}

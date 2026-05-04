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

variable "key_vault_id" {
  description = "ID of the Key Vault that holds the CMK. Must have purge protection + soft delete enabled."
  type        = string
}

variable "key_vault_uri" {
  description = "Vault URI of the Key Vault that holds the CMK."
  type        = string
}

variable "key_name" {
  description = "Logical name of the encryption key. Versionless reference is used so rotations are picked up automatically."
  type        = string
  default     = "data-ai-mcp-cmk"
}

variable "cmk_identity_name" {
  description = "Name of the user-assigned identity that CMK-using resources reference."
  type        = string
}

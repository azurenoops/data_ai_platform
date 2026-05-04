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

variable "key_vault_name" {
  type = string
}

variable "enable_purge_protection" {
  description = "Required when this vault holds a CMK key."
  type        = bool
  default     = false
}

variable "soft_delete_retention_in_days" {
  description = "Recommended >= 30 when holding CMK keys."
  type        = number
  default     = 7
}

variable "tenant_id" {
  type = string
}

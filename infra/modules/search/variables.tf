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

variable "search_name" {
  type = string
}

variable "sku" {
  type    = string
  default = "standard"

  validation {
    condition     = contains(["basic", "standard", "standard2", "standard3"], var.sku)
    error_message = "sku must be one of: basic, standard, standard2, standard3."
  }
}

variable "enforce_cmk" {
  description = "Enforce service-level CMK. Per-index encryption keys are still configured by the index provisioner."
  type        = bool
  default     = false
}

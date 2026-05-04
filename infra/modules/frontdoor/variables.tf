variable "resource_group_name" {
  type = string
}

variable "front_door_name" {
  type = string
}

variable "sku" {
  type    = string
  default = "Standard_AzureFrontDoor"

  validation {
    condition     = contains(["Standard_AzureFrontDoor", "Premium_AzureFrontDoor"], var.sku)
    error_message = "sku must be Standard_AzureFrontDoor or Premium_AzureFrontDoor."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "primary_origin_host_name" {
  type = string
}

variable "secondary_origin_host_name" {
  description = "Empty disables the secondary origin (FD still in front for WAF/edge)."
  type        = string
  default     = ""
}

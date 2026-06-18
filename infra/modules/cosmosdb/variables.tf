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

variable "account_name" {
  type = string
}

variable "database_name" {
  type = string
}

variable "source_config_container_name" {
  type = string
}

variable "public_network_access_enabled" {
  type    = bool
  default = true
}
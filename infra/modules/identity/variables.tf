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

variable "mcp_server_identity_name" {
  type = string
}

variable "ingestion_identity_name" {
  type = string
}

variable "data_factory_identity_name" {
  type = string
}

variable "portal_identity_name" {
  type = string
}

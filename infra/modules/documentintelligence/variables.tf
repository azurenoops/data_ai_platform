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

variable "cmk_key_uri" {
  description = "Versionless KV key URL. Empty disables CMK on the Document Intelligence account."
  type        = string
  default     = ""
}

variable "cmk_user_assigned_identity_id" {
  description = "UAMI resource ID used to wrap/unwrap CMK. Required when cmk_key_uri is set."
  type        = string
  default     = ""
}

variable "cmk_user_assigned_identity_client_id" {
  description = "Client ID of the CMK UAMI - required by Cognitive Services CMK to avoid SAMI bootstrap chicken-and-egg."
  type        = string
  default     = ""
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "rg_name" {
  description = "Resource group name"
  type        = string
}

variable "acr_name" {
  description = "Container registry name"
  type        = string
}

variable "acr_sku" {
  description = "Container registry SKU"
  type        = string
  default     = "Basic"
}

variable "kv_name" {
  description = "Key Vault name"
  type        = string
}

variable "kv_sku" {
  description = "Key Vault SKU"
  type        = string
  default     = "standard"
}

variable "soft_delete_retention_days" {
  description = "Soft delete retention days"
  type        = number
  default     = 7
}

variable "purge_protection_enabled" {
  description = "Enable purge protection"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
}

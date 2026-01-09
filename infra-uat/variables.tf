variable "location" {
  description = "Azure region"
  type        = string
}

variable "rg_name" {
  description = "Resource group name"
  type        = string
}

variable "aci_name" {
  description = "Container instance name"
  type        = string
}

variable "cpu" {
  description = "CPU cores"
  type        = string
  default     = "0.5"
}

variable "memory" {
  description = "Memory in GB"
  type        = string
  default     = "1"
}

variable "image_version" {
  description = "Docker image version (commit SHA or release tag)"
  type        = string
}

variable "dbt_target" {
  description = "DBT profile target (dev/uat/prd)"
  type        = string
}

variable "keyvault_url" {
  description = "Key Vault URL"
  type        = string
}

variable "cert_secret_name" {
  description = "Snowflake certificate secret name"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
}

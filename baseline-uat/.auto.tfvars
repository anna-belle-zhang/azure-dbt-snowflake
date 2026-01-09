location                   = "West Europe"
rg_name                    = "az-euw-syn-uat-pract-dbt-rg01"
acr_name                   = "dbtjobsuat"
acr_sku                    = "Basic"
kv_name                    = "secrets-aci-uat"
kv_sku                     = "standard"
soft_delete_retention_days = 30
purge_protection_enabled   = false

tags = {
  provider                = "az"
  region                  = "euw"
  enterprise              = "syn"
  account                 = "uat"
  system                  = "pract"
  environment             = "uat"
  cmdb_name               = "dbt-pipeline-uat"
  security_exposure_level = "MZ"
  status                  = "active"
  on_service              = "yes"
  managed_by              = "terraform"
  deployment_type         = "trunk-based"
}

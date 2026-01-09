location                   = "West Europe"
rg_name                    = "az-euw-syn-dev-pract-dbt-rg01"
acr_name                   = "dbtjobsdev"
acr_sku                    = "Basic"
kv_name                    = "secrets-aci-dev"
kv_sku                     = "standard"
soft_delete_retention_days = 7
purge_protection_enabled   = false

tags = {
  provider                = "az"
  region                  = "euw"
  enterprise              = "syn"
  account                 = "dev"
  system                  = "pract"
  environment             = "dev"
  cmdb_name               = "dbt-pipeline-dev"
  security_exposure_level = "MZ"
  status                  = "active"
  on_service              = "yes"
  managed_by              = "terraform"
  deployment_type         = "trunk-based"
}

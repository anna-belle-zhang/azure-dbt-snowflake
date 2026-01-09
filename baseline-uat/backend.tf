terraform {
  backend "azurerm" {
    resource_group_name  = "az-euw-syn-uat-pract-dbt-rg01"
    storage_account_name = "azeuwsynuatstategsa01"
    container_name       = "az-euw-syn-uat-tfstate-container01"
    key                  = "dbt_uat_baseline.terraform.tfstate"
  }
}

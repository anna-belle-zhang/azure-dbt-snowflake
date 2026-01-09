terraform {
  backend "azurerm" {
    resource_group_name  = "az-euw-syn-dev-pract-dbt-rg01"
    storage_account_name = "azeuwsyndevstategsa01"
    container_name       = "az-euw-syn-dev-tfstate-container01"
    key                  = "dbt_dev_baseline.terraform.tfstate"
  }
}

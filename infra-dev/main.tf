provider "azurerm" {
  features {}
}

locals {
  image_name = "${data.terraform_remote_state.azure_baseline.outputs.acr_login_server}/dbt/tpch_transform:${var.image_version}"
}

data "terraform_remote_state" "azure_baseline" {
  backend = "azurerm"
  config = {
    resource_group_name  = "az-euw-syn-dev-pract-dbt-rg01"
    storage_account_name = "azeuwsyndevstategsa01"
    container_name       = "az-euw-syn-dev-tfstate-container01"
    key                  = "dbt_dev_baseline.terraform.tfstate"
  }
}

resource "azurerm_container_group" "aci" {
  name                = var.aci_name
  location            = var.location
  resource_group_name = var.rg_name
  ip_address_type     = "Public"
  os_type             = "Linux"
  restart_policy      = "Never"

  container {
    name   = "dbt"
    image  = local.image_name
    cpu    = var.cpu
    memory = var.memory

    ports {
      port     = 80
      protocol = "TCP"
    }

    environment_variables = {
      ENV_KV_URL      = var.keyvault_url
      ENV_SNOW_SECRET = var.cert_secret_name
      DBT_TARGET      = var.dbt_target
      AZURE_CLIENT_ID = data.terraform_remote_state.azure_baseline.outputs.managed_identity_client_id
    }
  }

  image_registry_credential {
    server   = data.terraform_remote_state.azure_baseline.outputs.acr_login_server
    username = data.terraform_remote_state.azure_baseline.outputs.acr_admin_username
    password = data.terraform_remote_state.azure_baseline.outputs.acr_admin_password
  }

  identity {
    type = "UserAssigned"
    identity_ids = [
      data.terraform_remote_state.azure_baseline.outputs.managed_identity_id
    ]
  }

  tags = var.tags
}

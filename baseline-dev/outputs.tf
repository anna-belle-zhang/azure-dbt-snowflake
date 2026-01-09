output "rg_name" {
  value = azurerm_resource_group.rg.name
}

output "acr_name" {
  value = azurerm_container_registry.acr.name
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "acr_admin_username" {
  value     = azurerm_container_registry.acr.admin_username
  sensitive = true
}

output "acr_admin_password" {
  value     = azurerm_container_registry.acr.admin_password
  sensitive = true
}

output "keyvault_name" {
  value = azurerm_key_vault.keyvault.name
}

output "keyvault_uri" {
  value = azurerm_key_vault.keyvault.vault_uri
}

output "managed_identity_id" {
  value = azurerm_user_assigned_identity.aci.id
}

output "managed_identity_client_id" {
  value = azurerm_user_assigned_identity.aci.client_id
}

output "managed_identity_principal_id" {
  value = azurerm_user_assigned_identity.aci.principal_id
}

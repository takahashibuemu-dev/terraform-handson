output "handson_storage_account_name" {
  description = "The name of the Storage Account created by Terraform."
  value       = azurerm_storage_account.handson.name
}

output "target_resource_group_name" {
  description = "The Resource Group used in this handson."
  value       = data.azurerm_resource_group.target.name
}
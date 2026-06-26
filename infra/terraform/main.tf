data "azurerm_resource_group" "target" {
  name = var.target_resource_group_name
}

resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

locals {
  storage_account_name = "st${var.customer_name}${var.environment_name}${random_string.suffix.result}"

  common_tags = {
    customer    = var.customer_name
    environment = var.environment_name
    managed_by  = "terraform"
    purpose     = "handson"
    test        = "auto-apply"
  }
}

resource "azurerm_storage_account" "handson" {
  name                = local.storage_account_name
  resource_group_name = data.azurerm_resource_group.target.name
  location            = data.azurerm_resource_group.target.location

  account_tier             = "Standard"
  account_replication_type = "LRS"

  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  tags = local.common_tags
}

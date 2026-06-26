provider "azurerm" {
  features {}

  subscription_id = var.subscription_id

  skip_provider_registration = true
}
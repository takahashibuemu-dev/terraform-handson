variable "subscription_id" {
  description = "Azure Subscription ID."
  type        = string
}

variable "target_resource_group_name" {
  description = "The existing Resource Group where the handson Storage Account will be created."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "customer_name" {
  description = "Customer name for this handson."
  type        = string
}

variable "environment_name" {
  description = "Environment name for this handson."
  type        = string
}
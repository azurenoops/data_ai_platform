terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # Upper bound: azurerm 4.71.0 bumped the storage API to 2025-08-01, which
      # Azure Government does not yet support (max is 2025-06-01). Cap below
      # 4.71 until Gov adds 2025-08-01 support. The locked version (.terraform.lock.hcl)
      # is 4.70.0 — keep them aligned.
      version = ">= 4.18, < 4.71"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

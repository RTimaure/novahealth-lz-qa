terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }

  }

  # Remote state, isolated per environment via a distinct key.
  # Values for resource_group_name / storage_account_name / container_name
  # are intentionally omitted here and must be supplied at `terraform init`
  # time via `-backend-config` (see .github/workflows/terraform-apply.yml),
  # so the same code can target different backend storage per environment
  # without hardcoding secrets/state locations in version control.
  backend "azurerm" {
    key = "primary.tfstate"
  }
}

provider "azurerm" {
  skip_provider_registration = true
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azurerm" {
  alias                      = "connectivity"
  skip_provider_registration = true
  subscription_id            = var.connectivity_subscription_id
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  storage_use_azuread = true
}

provider "azurerm" {
  alias                      = "identity"
  subscription_id            = var.identity_subscription_id
  skip_provider_registration = true
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azurerm" {
  alias                      = "management"
  subscription_id            = var.management_subscription_id
  skip_provider_registration = true
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azurerm" {
  alias                      = "production"
  subscription_id            = var.production_subscription_id
  skip_provider_registration = true
  storage_use_azuread        = true
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azurerm" {
  alias                      = "platform_services"
  subscription_id            = var.platform_services_subscription_id
  skip_provider_registration = true
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azuread" {}


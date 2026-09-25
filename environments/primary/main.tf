
locals {
  target_subscriptions = {
    connectivity      = var.connectivity_subscription_id
    identity          = var.identity_subscription_id
    management        = var.management_subscription_id
    production        = var.production_subscription_id
    platform_services = var.platform_services_subscription_id
  }

  root_mg_id     = lookup(module.management_groups.management_group_ids, "root", "nh-root")
  security_mg_id = lookup(module.management_groups.management_group_ids, "security", "nh-security")
}

module "management_groups" {
  source = "../../modules/management_groups"
}

module "subscriptions" {
  source = "../../modules/subscriptions"

  management_group_ids         = module.management_groups.management_group_ids
  use_enterprise_subscriptions = var.use_enterprise_subscriptions
  enterprise_subscriptions     = var.enterprise_subscriptions
  subscription_to_mg           = var.subscription_to_mg
  student_subscription_id      = var.student_subscription_id

  depends_on = [module.management_groups]
}

module "resource_groups" {
  source = "../../modules/resource_groups"

  primary_location = var.primary_location
  dr_location      = var.dr_location
  deployment_scope = var.deployment_scope

  providers = {
    azurerm.connectivity      = azurerm.connectivity
    azurerm.identity          = azurerm.identity
    azurerm.management        = azurerm.management
    azurerm.production        = azurerm.production
    azurerm.platform_services = azurerm.platform_services
  }

  depends_on = [module.subscriptions]
}

module "policy" {
  source = "../../modules/policy"

  root_mg_id           = local.root_mg_id
  platform_mg_id       = lookup(module.management_groups.management_group_ids, "platform", "nh-platform")
  landing_zones_mg_id  = lookup(module.management_groups.management_group_ids, "landing_zones", "nh-landing-zones")
  management_group_ids = module.management_groups.management_group_ids
  target_subscriptions = local.target_subscriptions
  allowed_locations    = [var.location]

  depends_on = [module.management_groups]
}

module "rbac" {
  source = "../../modules/rbac"

  root_mg_id                       = local.root_mg_id
  security_mg_id                   = local.security_mg_id
  target_subscriptions             = local.target_subscriptions
  cicd_service_principal_object_id = var.cicd_service_principal_object_id

  depends_on = [module.policy]
}

module "networking" {
  source               = "../../modules/networking"
  location             = var.location
  target_subscriptions = local.target_subscriptions
  resource_group_names = module.resource_groups.rg_names
  #resource_group_tags  = module.resource_groups.rg_tags

  enable_global_peering        = var.enable_global_peering
  remote_hub_vnet_id           = var.remote_hub_vnet_id
  tags                         = var.tags
  enable_onprem_vpn_simulation = var.enable_onprem_vpn_simulation
  vpn_shared_key               = var.vpn_shared_key

  providers = {
    azurerm.connectivity      = azurerm.connectivity
    azurerm.identity          = azurerm.identity
    azurerm.management        = azurerm.management
    azurerm.production        = azurerm.production
    azurerm.platform_services = azurerm.platform_services
  }

  depends_on = [module.resource_groups]
}


module "finops" {
  source = "../../modules/finops"

  target_subscriptions = local.target_subscriptions
  notification_emails  = ["finops@novahealth.com"]

  #	depends_on = [module.networking]
}

module "observability" {
  source = "../../modules/observability"

  location             = var.location
  resource_group_names = module.resource_groups.rg_names
  #resource_group_tags  = module.resource_groups.rg_tags
  tags               = var.tags
  notification_email = "ops-alerts@novahealth.com"

  diagnostic_target_resources = {
    firewall_id            = module.networking.firewall_id
    application_gateway_id = module.networking.application_gateway_id
    vpn_gateway_id         = module.networking.vpn_gateway_id
    bastion_id             = module.networking.bastion_id
    dns_resolver_id        = module.networking.dns_resolver_id
  }

  # 🆕(Dile a Terraform explícitamente qué recursos existen)
  enabled_features = {
    firewall            = true
    application_gateway = true
    vpn_gateway         = true
    bastion             = true
    dns_resolver        = true
  }

  providers = {
    azurerm = azurerm.management
  }

  #depends_on = [module.resource_groups, module.networking]
  depends_on = [module.resource_groups]
}


#------------------------------------------------------------------------
# JUMPBOX (VM para el acceso seguro via bastion a la red corporativa)
#------------------------------------------------------------------------
module "jumpbox" {
  source = "../../modules/jumpbox"

  providers = {
    azurerm = azurerm.connectivity
  }

  location            = var.primary_location
  resource_group_name = module.resource_groups.rg_names["rg-mgmtvm-prod-swe"]
  subnet_id           = module.networking.subnets["hub_prod_snet-hub-mngt-prod-swe"]
  tags                = module.resource_groups.rg_tags["rg-mgmtvm-prod-swe"]

  environment   = "prod"
  region_suffix = "swe"

  admin_username = var.jumpbox_admin_username
  admin_password = var.jumpbox_admin_password

  log_analytics_workspace_id  = module.observability.log_analytics_workspace_id
  log_analytics_workspace_key = module.observability.log_analytics_workspace_primary_shared_key

  #depends_on = [module.networking, module.observability, module.resource_groups]
}

# =========================================================================
# VM TESTER (PRUEBAS DE CONECTIVIDAD)
# =========================================================================

locals {
  test_vm_spoke_map = {
    aks = {
      subnet_key   = "aks_prod_snet-aks-workload-prod-swe"
      rg_key       = "rg-aks-prod-swe"
      nsg_key      = "aks_prod_snet-aks-workload-prod-swe"
      provider_grp = "production"
    }
    apps = {
      subnet_key   = "apps_prod_snet-apps-messaging-prod-swe"
      rg_key       = "rg-apps-prod-swe"
      nsg_key      = "apps_prod_snet-apps-messaging-prod-swe"
      provider_grp = "production"
    }
    dataai = {
      subnet_key   = "dataai_prod_snet-dataai-compute-prod-swe"
      rg_key       = "rg-dataai-prod-swe"
      nsg_key      = "dataai_prod_snet-dataai-compute-prod-swe"
      provider_grp = "platform_services"
    }
    shared = {
      subnet_key   = "shared_prod_snet-shared-devops-prod-swe"
      rg_key       = "rg-sharedservices-prod-swe"
      nsg_key      = "shared_prod_snet-shared-devops-prod-swe"
      provider_grp = "platform_services"
    }
  }

  test_vm_selected = local.test_vm_spoke_map[var.test_vm_spoke]

  test_vm_tags = merge(var.tags, {
    environmentType = "primary"
    environment     = "prod"
    region          = "SwedenCentral"
    owner           = "grp-novahealth-network-team"
    costCenter      = "CC-004"
    project         = "NovaHealth-LandingZone"
    workload        = "platformshared-services"
    criticality     = "Low"
  })
}

module "test_vm" {
  source = "../../modules/test_vm"

  providers = {
    azurerm.target = azurerm.platform_services
  }

  location                         = var.location
  resource_group_name              = module.resource_groups.rg_names[local.test_vm_selected.rg_key]
  subnet_id                        = module.networking.subnets[local.test_vm_selected.subnet_key]
  existing_nsg_name                = module.networking.nsgs[local.test_vm_selected.nsg_key].name
  existing_nsg_resource_group_name = module.networking.nsgs[local.test_vm_selected.nsg_key].resource_group_name

  vm_scope       = var.test_vm_spoke
  environment    = "prod"
  region_suffix  = "swe"
  admin_password = var.test_vm_admin_password
  tags           = local.test_vm_tags

  #depends_on = [module.networking]
}

# =========================================================================
# RAG INFRASTRUCTURE (CHATBOT DE GOBERNANZA — Arquitectura RAG v2.4)
# =========================================================================
# Se despliega en el dominio Apps (suscripción production, RG dedicado
# rg-rag-prod-swe), reutilizando la VNet/subredes de ese dominio y las
# zonas DNS privadas (blob, search, openai, redis) ya creadas por
# modules/networking.
module "rag_infrastructure" {
  source = "../../modules/rag_infrastructure"

  providers = {
    azurerm = azurerm.production
  }

  #RT: Configuración de acceso público a GitHub Actions para el despliegue de RAG 25.09
  allow_public_network_access = true
  cicd_allowed_ip_ranges      = [] # dejar vacío, se completa con GitHub meta dinámicamente

  location         = var.primary_location
  environment_name = "prod"
  region_suffix    = "swe"

  resource_group_name = module.resource_groups.rg_names["rg-rag-prod-swe"]
  tags                = module.resource_groups.rg_tags["rg-rag-prod-swe"]

  aca_infrastructure_subnet_id = module.networking.subnets["apps_prod_snet-apps-aca-prod-swe"]
  private_endpoint_subnet_id   = module.networking.subnets["apps_prod_snet-apps-pe-prod-swe"]
  private_dns_zone_ids         = module.networking.private_dns_zones

  log_analytics_workspace_id             = module.observability.log_analytics_workspace_id
  application_insights_connection_string = module.observability.application_insights_connection_string

  storage_account_name            = var.rag_storage_account_name
  search_service_name             = var.rag_search_service_name
  search_bootstrap_allowed_ips    = var.search_bootstrap_allowed_ips #AÑADIDO PARA TS 19.09
  search_bootstrap_auto_detect_ip = var.search_bootstrap_auto_detect_ip
  openai_account_name             = var.rag_openai_account_name

  create_container_registry = true
  container_registry_name   = var.rag_container_registry_name

  container_app_environment_name = "cae-rag-prod-swe"

  create_entra_groups = var.rag_create_entra_groups
  entra_group_owners  = var.rag_entra_group_owners



  #depends_on = [module.networking, module.observability, module.resource_groups]
}


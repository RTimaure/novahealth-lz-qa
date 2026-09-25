variable "location" {
  description = "Región de despliegue para primary."
  type        = string
  default     = "swedencentral"

  validation {
    condition     = contains(["swedencentral", "francecentral"], var.location)
    error_message = "La ubicación debe ser swedencentral o francecentral."
  }
}

variable "primary_location" {
  description = "Región primaria."
  type        = string
  default     = "swedencentral"
}

variable "dr_location" {
  description = "Región DR."
  type        = string
  default     = "francecentral"
}

variable "deployment_scope" {
  description = "Alcance del despliegue físico."
  type        = string
  default     = "primary"

  validation {
    condition     = contains(["primary", "dr"], var.deployment_scope)
    error_message = "deployment_scope debe ser primary o dr."
  }
}

variable "use_enterprise_subscriptions" {
  description = "Activa el modo enterprise para asociar suscripciones reales."
  type        = bool
  default     = true
}

variable "enterprise_subscriptions" {
  description = "Mapa de suscripciones enterprise del entorno primary."
  type        = map(string)
  default     = {}
}

variable "subscription_to_mg" {
  description = "Mapa de asociación entre suscripciones y management groups."
  type        = map(string)
  default     = {}
}

variable "student_subscription_id" {
  description = "ID de suscripción de estudiante, mantenido por compatibilidad."
  type        = string
  default     = ""
}

variable "connectivity_subscription_id" {
  description = "Subscription ID de connectivity."
  type        = string
}

variable "identity_subscription_id" {
  description = "Subscription ID de identity."
  type        = string
}

variable "management_subscription_id" {
  description = "Subscription ID de management."
  type        = string
}

variable "production_subscription_id" {
  description = "Subscription ID de production."
  type        = string
}

variable "platform_services_subscription_id" {
  description = "Subscription ID de platform_services."
  type        = string
}

variable "tags" {
  description = "Etiquetas corporativas aplicadas a primary."
  type        = map(string)
  default     = {}
}

variable "enable_global_peering" {
  description = "Habilita el peering global inter-región con el Hub DR."
  type        = bool
  default     = false
}

variable "remote_hub_vnet_id" {
  description = "ID opcional de la VNet del Hub DR en FranceCentral."
  type        = string
  default     = null
}

variable "cicd_service_principal_object_id" {

  description = "Object ID del service principal de CI/CD."
  type        = string
  default     = ""
}

#--------------------------------------------
# Variables para el módulo de Jumpbox
#--------------------------------------------
variable "jumpbox_admin_username" {
  description = "Usuario administrador de la jumpbox"
  type        = string
  default     = "nh-jumpbox-admin"
}

variable "jumpbox_admin_password" {
  description = "Contraseña del usuario administrador de la jumpbox"
  type        = string
  sensitive   = true
}

#--------------------------------------------
# Variables para el módulo de VM Tester
#--------------------------------------------

variable "test_vm_spoke" {
  description = "Spoke destino de la VM de pruebas: aks | apps | dataai | shared"
  type        = string

  validation {
    condition     = contains(["aks", "apps", "dataai", "shared"], var.test_vm_spoke)
    error_message = "test_vm_spoke debe ser uno de: aks, apps, dataai, shared."
  }
}

variable "test_vm_admin_password" {
  description = "Contraseña del usuario administrador local de las VMs de prueba (sensible; no se abre el puerto 22 por red)."
  type        = string
  sensitive   = true
}

#--------------------------------------------
# Variables para el módulo de Infraestructura RAG (Chatbot de gobernanza)
#--------------------------------------------

variable "rag_storage_account_name" {
  description = "Nombre globalmente único del Storage Account de documentos del RAG (3-24 caracteres, minúsculas/dígitos)."
  type        = string
  default     = "stnhragprodswe01"
}

variable "rag_search_service_name" {
  description = "Nombre globalmente único del servicio Azure AI Search del RAG."
  type        = string
  default     = "srch-nh-rag-prod-swe"
}

variable "rag_openai_account_name" {
  description = "Nombre globalmente único de la cuenta Azure OpenAI del RAG."
  type        = string
  default     = "oai-nh-rag-prod-swe"
}

variable "rag_container_registry_name" {
  description = "Nombre globalmente único del Azure Container Registry donde novahealth-apps publica las imágenes de rag-api y rag-ingestion."
  type        = string
  default     = "acrnhragprodswe"
}

variable "rag_create_entra_groups" {
  description = "Si es true, crea los grupos de Entra ID de gobernanza del chatbot RAG. Debe activarse solo en un entorno (por defecto, primary) para evitar duplicados."
  type        = bool
  default     = true
}

variable "rag_entra_group_owners" {
  description = "Lista de Object IDs que serán propietarios de los grupos de Entra ID del chatbot RAG."
  type        = list(string)
  #default     = []
}

variable "enable_onprem_vpn_simulation" {
  description = "Activa el despliegue de la simulación VPN Hub <-> On-Premise."
  type        = bool
  default     = false
}

variable "vpn_shared_key" {
  description = "PSK de la conexión VPN simulada Hub <-> On-Premise."
  type        = string
  sensitive   = true
  default     = ""
}

#AÑADIDO PARA TS 19.09
variable "search_bootstrap_allowed_ips" {
  description = "IP pública del operador para el bootstrap del índice de AI Search (vacío tras el primer apply)."
  type        = list(string)
  default     = []
}

variable "search_bootstrap_auto_detect_ip" {
  description = "Si es true, detecta automáticamente la IP pública de quién ejecuta 'apply' para el bootstrap del índice de AI Search, en vez de depender de search_bootstrap_allowed_ips. Vuelve a false una vez creado el índice."
  type        = bool
  default     = false
}

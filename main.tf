provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = "fcb74088-4f4d-4899-8bda-ebc92c868342"  # Your Azure for Students subscription ID
}

# Random string for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Resource Group (a container for all resources)
resource "azurerm_resource_group" "rg" {
  name     = "event-pipeline-rg"
  location = "West US"
}

# Storage Account (for Blob Storage)
resource "azurerm_storage_account" "storage" {
  name                     = "mypipelinedata${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Blob Container (to store files)
resource "azurerm_storage_container" "container" {
  name                  = "data"
  storage_account_id    = azurerm_storage_account.storage.id
  container_access_type = "private"
}

# Cosmos DB (to store processed data)
resource "azurerm_cosmosdb_account" "cosmos" {
  name                = "mypipeline-cosmos-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  consistency_policy {
    consistency_level = "Session"
  }
  geo_location {
    location          = azurerm_resource_group.rg.location
    failover_priority = 0
  }
}

# Cosmos DB Database
resource "azurerm_cosmosdb_sql_database" "db" {
  name                = "pipeline-db"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
}

# Cosmos DB Container
resource "azurerm_cosmosdb_sql_container" "container" {
  name                = "data"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
  database_name       = azurerm_cosmosdb_sql_database.db.name
  partition_key_paths = ["/id"]
}

# Service Plan (for Function App)
resource "azurerm_service_plan" "plan" {
  name                = "pipeline-plan"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "Y1"
}

# Function App
resource "azurerm_linux_function_app" "function" {
  name                       = "pipeline-function-${random_string.suffix.result}"
  resource_group_name        = azurerm_resource_group.rg.name
  location                   = azurerm_resource_group.rg.location
  service_plan_id            = azurerm_service_plan.plan.id
  storage_account_name       = azurerm_storage_account.storage.name
  storage_account_access_key = azurerm_storage_account.storage.primary_access_key
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME" = "node"
    "COSMOSDB_ENDPOINT"        = azurerm_cosmosdb_account.cosmos.endpoint
    "COSMOSDB_KEY"            = azurerm_cosmosdb_account.cosmos.primary_key
  }
  site_config {}  # Required for azurerm_linux_function_app
}

# Data Factory (for daily reports)
resource "azurerm_data_factory" "adf" {
  name                = "pipeline-adf-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}
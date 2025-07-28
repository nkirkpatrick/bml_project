#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="${APP_NAME:-django-app}"
LOCATION="${LOCATION:-eastus}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-${APP_NAME}}"

echo -e "${GREEN}🚀 Starting Django App Deployment to Azure App Service${NC}"
echo "App Name: $APP_NAME"
echo "Location: $LOCATION"
echo "Resource Group: $RESOURCE_GROUP"

# Check if required tools are installed
check_dependencies() {
    echo -e "${YELLOW}📋 Checking dependencies...${NC}"
    
    if ! command -v azd &> /dev/null; then
        echo -e "${RED}❌ Azure Developer CLI (azd) is not installed${NC}"
        echo "Install from: https://docs.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd"
        exit 1
    fi
    
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}❌ Terraform is not installed${NC}"
        echo "Install from: https://www.terraform.io/downloads.html"
        exit 1
    fi
    
    if ! command -v az &> /dev/null; then
        echo -e "${RED}❌ Azure CLI is not installed${NC}"
        echo "Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    echo -e "${GREEN}✅ All dependencies are installed${NC}"
}

# Initialize Azure Developer CLI project
init_azd() {
    echo -e "${YELLOW}🔧 Initializing Azure Developer CLI...${NC}"
    
    if [ ! -f "azure.yaml" ]; then
        # Try different approaches to initialize azd
        if azd init --help | grep -q "\-\-template"; then
            # Try with empty template first
            echo -e "${YELLOW}📝 Attempting to initialize with empty project...${NC}"
            if ! azd init --template empty 2>/dev/null; then
                # If empty template fails, try without template
                echo -e "${YELLOW}📝 Trying azd init without template...${NC}"
                if ! azd init 2>/dev/null; then
                    # If that fails, create files manually
                    echo -e "${YELLOW}📝 Creating azd configuration manually...${NC}"
                    create_azd_files_manually
                fi
            fi
        else
            # Older version of azd, try without template
            echo -e "${YELLOW}📝 Using azd init without template (older version)...${NC}"
            if ! azd init 2>/dev/null; then
                create_azd_files_manually
            fi
        fi
        
        # Always ensure we have the correct azure.yaml content
        create_azure_yaml
    fi
    
    echo -e "${GREEN}✅ Azure Developer CLI initialized${NC}"
}

# Create azd files manually if templates fail
create_azd_files_manually() {
    echo -e "${YELLOW}📝 Creating Azure Developer CLI files manually...${NC}"
    
    # Create .azure directory structure
    mkdir -p .azure/${APP_NAME}
    
    # Create basic azd environment
    cat > .azure/${APP_NAME}/.env << EOF
AZURE_ENV_NAME=${APP_NAME}
AZURE_LOCATION=${LOCATION}
AZURE_SUBSCRIPTION_ID=
EOF
}

# Create or update azure.yaml
create_azure_yaml() {
    echo -e "${YELLOW}📝 Creating azure.yaml configuration...${NC}"
    
    cat > azure.yaml << EOF
name: ${APP_NAME}
metadata:
  template: ${APP_NAME}@0.0.1-beta
services:
  api:
    project: .
    language: py
    host: appservice
infra:
  provider: terraform
  path: ./infra
EOF
}

# Create Terraform infrastructure files
create_terraform_files() {
    echo -e "${YELLOW}🏗️  Creating Terraform infrastructure files...${NC}"
    
    mkdir -p infra
    
    # Main Terraform configuration
    cat > infra/main.tf << 'EOF'
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
    azurecaf = {
      source  = "aztfmod/azurecaf"
      version = "~>1.2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Generate random suffix for unique naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

# App Service Plan
resource "azurerm_service_plan" "main" {
  name                = "asp-${var.app_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  os_type            = "Linux"
  sku_name           = var.app_service_sku
}

# App Service
resource "azurerm_linux_web_app" "main" {
  name                = "app-${var.app_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_service_plan.main.location
  service_plan_id    = azurerm_service_plan.main.id

  site_config {
    application_stack {
      python_version = "3.11"
    }
    
    # Use the startup script we created
    app_command_line = "./startup.sh"
  }

  app_settings = {
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "1"
    "DJANGO_SETTINGS_MODULE"         = "${var.django_project_name}.production_settings"
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
    "DEBUG"                          = "False"
    "ALLOWED_HOSTS"                  = "*.azurewebsites.net"
    "DB_NAME"                        = azurerm_postgresql_flexible_server_database.main.name
    "DB_USER"                        = azurerm_postgresql_flexible_server.main.administrator_login
    "DB_PASSWORD"                    = azurerm_postgresql_flexible_server.main.administrator_password
    "DB_HOST"                        = azurerm_postgresql_flexible_server.main.fqdn
    "DB_PORT"                        = "5432"
    "SECRET_KEY"                     = var.django_secret_key
  }

  connection_string {
    name  = "DefaultConnection"
    type  = "PostgreSQL"
    value = "Server=${azurerm_postgresql_flexible_server.main.fqdn};Database=${azurerm_postgresql_flexible_server_database.main.name};Port=5432;User Id=${azurerm_postgresql_flexible_server.main.administrator_login};Password=${azurerm_postgresql_flexible_server.main.administrator_password};Ssl Mode=Require;"
  }
}

# PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "main" {
  name                   = "psql-${var.app_name}-${random_string.suffix.result}"
  resource_group_name    = azurerm_resource_group.main.name
  location              = azurerm_resource_group.main.location
  version               = "13"
  administrator_login    = "postgres"
  administrator_password = var.database_password
  zone                  = "1"
  storage_mb            = 32768
  sku_name              = "B_Standard_B1ms"
  backup_retention_days = 7
}

# PostgreSQL Database
resource "azurerm_postgresql_flexible_server_database" "main" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.main.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

# PostgreSQL Firewall Rule
resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}
EOF

    # Variables file
    cat > infra/variables.tf << 'EOF'
variable "app_name" {
  description = "The name of the application"
  type        = string
  default     = "django-app"
}

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
}

variable "resource_group_name" {
  description = "The name of the resource group"
  type        = string
}

variable "app_service_sku" {
  description = "The SKU for the App Service Plan"
  type        = string
  default     = "B1"
}

variable "database_name" {
  description = "The name of the PostgreSQL database"
  type        = string
  default     = "djangodb"
}

variable "django_project_name" {
  description = "The name of the Django project"
  type        = string
}

variable "database_password" {
  description = "The password for the PostgreSQL server"
  type        = string
  sensitive   = true
}

variable "django_project_name" {
  description = "The name of the Django project"
  type        = string
}

variable "django_secret_key" {
  description = "The Django secret key"
  type        = string
  sensitive   = true
}
EOF

    # Outputs file
    cat > infra/outputs.tf << 'EOF'
output "app_service_name" {
  description = "The name of the App Service"
  value       = azurerm_linux_web_app.main.name
}

output "app_service_hostname" {
  description = "The hostname of the App Service"
  value       = azurerm_linux_web_app.main.default_hostname
}

output "app_service_url" {
  description = "The URL of the App Service"
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "postgresql_server_name" {
  description = "The name of the PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.main.name
}
EOF

    # Detect Django project name if not provided
    if [ -z "$DJANGO_PROJECT_NAME" ]; then
        DJANGO_PROJECT_NAME=$(python -c "
import os, sys
sys.path.append('.')
settings_files = []
for root, dirs, files in os.walk('.'):
    if 'settings.py' in files and root != '.':
        settings_files.append(root)
if settings_files:
    print(settings_files[0].replace('./', '').replace('/', ''))
" 2>/dev/null)
    fi
    
    if [ -z "$DJANGO_PROJECT_NAME" ]; then
        DJANGO_PROJECT_NAME="myproject"
        echo -e "${YELLOW}⚠️  Could not detect Django project name, using 'myproject'${NC}"
    fi
    
    # Generate a random secret key
    DJANGO_SECRET_KEY=$(python -c "
import secrets
import string
alphabet = string.ascii_letters + string.digits + '!@#$%^&*(-_=+)'
print(''.join(secrets.choice(alphabet) for i in range(50)))
")
    
    # Terraform variables file
    cat > infra/terraform.tfvars << EOF
app_name = "${APP_NAME}"
location = "${LOCATION}"
resource_group_name = "${RESOURCE_GROUP}"
database_password = "P@ssw0rd123!"
django_project_name = "${DJANGO_PROJECT_NAME}"
django_secret_key = "${DJANGO_SECRET_KEY}"
EOF

    echo -e "${GREEN}✅ Terraform files created${NC}"
}

# Prepare existing Django project for deployment
prepare_existing_django() {
    echo -e "${YELLOW}🐍 Preparing existing Django project for Azure deployment...${NC}"
    
    # Check if we're in a Django project directory
    if [ ! -f "manage.py" ]; then
        echo -e "${RED}❌ No manage.py found. Make sure you're in your Django project root directory${NC}"
        echo -e "${YELLOW}💡 Your project structure should look like:${NC}"
        echo "   your-project/"
        echo "   ├── manage.py"
        echo "   ├── your_project_name/"
        echo "   │   ├── settings.py"
        echo "   │   └── ..."
        echo "   └── ..."
        exit 1
    fi
    
    # Find the Django project name automatically
    DJANGO_PROJECT_NAME=$(python -c "
import os, sys
sys.path.append('.')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', '$(find . -name "settings.py" | head -1 | sed 's|./||' | sed 's|/settings.py||').settings')
import django
django.setup()
from django.conf import settings
print(settings.SETTINGS_MODULE.split('.')[0])
" 2>/dev/null)
    
    if [ -z "$DJANGO_PROJECT_NAME" ]; then
        # Fallback: find project name from directory structure
        DJANGO_PROJECT_NAME=$(find . -name "settings.py" -path "*/*/settings.py" | head -1 | cut -d'/' -f2)
    fi
    
    if [ -z "$DJANGO_PROJECT_NAME" ]; then
        echo -e "${RED}❌ Could not detect Django project name${NC}"
        echo -e "${YELLOW}💡 Please ensure your project has the standard Django structure${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Detected Django project: $DJANGO_PROJECT_NAME${NC}"
    
    # Create or update requirements.txt with Azure-specific dependencies
    echo -e "${YELLOW}📦 Updating requirements.txt for Azure deployment...${NC}"
    
    # Backup existing requirements if it exists
    if [ -f "requirements.txt" ]; then
        cp requirements.txt requirements.txt.backup
        echo -e "${BLUE}ℹ️  Backed up existing requirements.txt to requirements.txt.backup${NC}"
    fi
    
    # Create new requirements.txt with existing + Azure dependencies
    {
        if [ -f "requirements.txt.backup" ]; then
            # Include existing requirements, but filter out potentially problematic ones
            cat requirements.txt.backup | grep -v "^psycopg2==" | grep -v "^gunicorn=="
        fi
        echo ""
        echo "# Azure deployment dependencies"
        echo "gunicorn>=20.1.0"
        echo "psycopg2-binary>=2.9.0"
        echo "python-decouple>=3.8"
        echo "whitenoise>=6.0.0"
    } > requirements.txt
    
    # Create production settings file
    create_production_settings
    
    # Create or update .env file for local development
    create_env_file
    
    # Create Azure-specific files
    create_azure_files
    
    echo -e "${GREEN}✅ Django project prepared for Azure deployment${NC}"
}

# Create production settings file
create_production_settings() {
    echo -e "${YELLOW}⚙️  Creating production settings...${NC}"
    
    PROD_SETTINGS_FILE="${DJANGO_PROJECT_NAME}/production_settings.py"
    
    cat > "$PROD_SETTINGS_FILE" << EOF
# Azure production settings
from .settings import *
from decouple import config
import os

# Security settings for production
DEBUG = config('DEBUG', default=False, cast=bool)
SECRET_KEY = config('SECRET_KEY', default=SECRET_KEY)

# Allow Azure App Service host
ALLOWED_HOSTS = config('ALLOWED_HOSTS', default='*').split(',')

# Database configuration for Azure PostgreSQL
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': config('DB_NAME', default='djangodb'),
        'USER': config('DB_USER', default='postgres'),
        'PASSWORD': config('DB_PASSWORD', default=''),
        'HOST': config('DB_HOST', default='localhost'),
        'PORT': config('DB_PORT', default='5432'),
        'OPTIONS': {
            'sslmode': 'require',
        },
    }
}

# Static files configuration for Azure
STATIC_URL = '/static/'
STATIC_ROOT = os.path.join(BASE_DIR, 'staticfiles')

# Add WhiteNoise middleware if not present
if 'whitenoise.middleware.WhiteNoiseMiddleware' not in MIDDLEWARE:
    # Insert WhiteNoise after SecurityMiddleware
    security_index = None
    for i, middleware in enumerate(MIDDLEWARE):
        if 'SecurityMiddleware' in middleware:
            security_index = i
            break
    
    if security_index is not None:
        MIDDLEWARE = MIDDLEWARE[:security_index+1] + ['whitenoise.middleware.WhiteNoiseMiddleware'] + MIDDLEWARE[security_index+1:]
    else:
        MIDDLEWARE = ['whitenoise.middleware.WhiteNoiseMiddleware'] + MIDDLEWARE

# Static files storage
STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'

# Security settings
SECURE_BROWSER_XSS_FILTER = True
SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = 'DENY'

# Logging configuration
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
        },
    },
    'loggers': {
        'django': {
            'handlers': ['console'],
            'level': config('DJANGO_LOG_LEVEL', default='INFO'),
        },
    },
}
EOF

    echo -e "${GREEN}✅ Production settings created at $PROD_SETTINGS_FILE${NC}"
}

# Create .env file for local development
create_env_file() {
    if [ ! -f ".env" ]; then
        echo -e "${YELLOW}📝 Creating .env file for local development...${NC}"
        
        cat > .env << EOF
# Local development settings
DEBUG=True
SECRET_KEY=your-local-secret-key-change-this-in-production
ALLOWED_HOSTS=localhost,127.0.0.1

# Local database (if using PostgreSQL locally)
DB_NAME=your_local_db
DB_USER=your_local_user
DB_PASSWORD=your_local_password
DB_HOST=localhost
DB_PORT=5432

# Django log level
DJANGO_LOG_LEVEL=DEBUG
EOF
        
        echo -e "${GREEN}✅ .env file created for local development${NC}"
        echo -e "${YELLOW}💡 Please update .env with your local database credentials${NC}"
    else
        echo -e "${BLUE}ℹ️  .env file already exists, skipping creation${NC}"
    fi
}

# Create Azure-specific files
create_azure_files() {
    echo -e "${YELLOW}☁️  Creating Azure-specific configuration files...${NC}"
    
    # Create startup script for App Service
    cat > startup.sh << EOF
#!/bin/bash

# Install dependencies
python -m pip install --upgrade pip
pip install -r requirements.txt

# Collect static files
python manage.py collectstatic --noinput

# Run migrations
python manage.py migrate --noinput

# Start Gunicorn
exec gunicorn --bind=0.0.0.0 --timeout 600 ${DJANGO_PROJECT_NAME}.wsgi:application
EOF
    
    chmod +x startup.sh
    
    # Create .deployment file for App Service
    cat > .deployment << EOF
[config]
SCM_DO_BUILD_DURING_DEPLOYMENT=1
EOF
    
    echo -e "${GREEN}✅ Azure configuration files created${NC}"
}

# Main deployment function
deploy() {
    echo -e "${YELLOW}🚀 Starting deployment...${NC}"
    
    # Login to Azure if not already logged in
    if ! az account show &> /dev/null; then
        echo -e "${YELLOW}🔐 Logging into Azure...${NC}"
        az login
    fi
    
    # Deploy with azd
    echo -e "${YELLOW}☁️  Deploying to Azure...${NC}"
    azd up --confirm-provisioning
    
    echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
    
    # Get the app URL
    APP_URL=$(azd show --output json | jq -r '.services.api.resourceId' | xargs az webapp show --ids | jq -r '.defaultHostName')
    if [ "$APP_URL" != "null" ] && [ -n "$APP_URL" ]; then
        echo -e "${GREEN}🌐 Your Django app is available at: https://$APP_URL${NC}"
    fi
}

# Main execution
main() {
    check_dependencies
    init_azd
    create_terraform_files
    prepare_existing_django
    deploy
}

# Run main function
main "$@"


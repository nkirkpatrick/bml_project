I've created a comprehensive cleanup script that specifically matches the resources created by your deploy.sh file. This script:
Key Features:

Matches your deploy.sh configuration - Uses the same environment variables (APP_NAME, LOCATION, RESOURCE_GROUP)
Two cleanup methods:

Preferred: Uses azd down to cleanly destroy the infrastructure (if Azure Developer CLI is available)
Fallback: Manual cleanup using Azure CLI for each resource type


Handles all resources created by your deploy.sh:

Django App Service (Linux Web App)
App Service Plan
PostgreSQL Flexible Server
PostgreSQL Database
Firewall rules
Resource Group


Smart deletion order - Deletes resources in the correct dependency order to avoid errors
Local file cleanup - Optionally removes local azd configuration files, Terraform files, and Azure-specific files created during deployment

Usage:

Set the same environment variables used in your deployment:
bashexport APP_NAME="your-app-name"
export LOCATION="eastus"
export RESOURCE_GROUP="rg-your-app-name"

Make executable and run:
bashchmod +x cleanup.sh
./cleanup.sh


Safety Features:

Confirmation prompts before deleting resources
Status checks to verify Azure login and resource existence
Graceful fallbacks if azd is not available
Final status check to confirm cleanup completion
Colored output for better visibility of the process

The script will first try to use azd down (which is the cleanest method since it uses the same infrastructure definition), and if that's not available or fails, it will fall back to manually deleting each resource type using the Azure CLI.RetryClaude does not have the ability to run the code it generates yet.Claude can make mistakes. Please double-check responses.
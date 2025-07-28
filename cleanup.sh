#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - these should match your deploy.sh variables
APP_NAME="${APP_NAME:-django-app}"
LOCATION="${LOCATION:-eastus}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-${APP_NAME}}"

echo -e "${RED}🗑️  Azure Django App Cleanup Script${NC}"
echo "App Name: $APP_NAME"
echo "Location: $LOCATION"
echo "Resource Group: $RESOURCE_GROUP"
echo ""

# Check if required tools are installed
check_dependencies() {
    echo -e "${YELLOW}📋 Checking dependencies...${NC}"
    
    if ! command -v azd &> /dev/null; then
        echo -e "${YELLOW}⚠️  Azure Developer CLI (azd) is not installed${NC}"
        echo -e "${BLUE}ℹ️  Will use Azure CLI only for cleanup${NC}"
        AZD_AVAILABLE=false
    else
        AZD_AVAILABLE=true
    fi
    
    if ! command -v az &> /dev/null; then
        echo -e "${RED}❌ Azure CLI is not installed${NC}"
        echo "Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Required dependencies are available${NC}"
}

# Check if user is logged in to Azure
check_azure_login() {
    echo -e "${YELLOW}🔐 Checking Azure login status...${NC}"
    
    if ! az account show &> /dev/null; then
        echo -e "${RED}❌ Not logged in to Azure${NC}"
        echo -e "${YELLOW}Please run 'az login' first${NC}"
        exit 1
    fi
    
    CURRENT_SUBSCRIPTION=$(az account show --query name -o tsv)
    echo -e "${GREEN}✅ Logged in to Azure subscription: $CURRENT_SUBSCRIPTION${NC}"
}

# Function to check if resource exists
resource_exists() {
    local resource_id=$1
    az resource show --ids "$resource_id" &> /dev/null
    return $?
}

# Function to get resources by pattern
get_resources_by_pattern() {
    local pattern=$1
    local resource_group=$2
    
    az resource list --resource-group "$resource_group" --query "[?contains(name, '$pattern')].{id:id,name:name,type:type}" -o json 2>/dev/null || echo "[]"
}

# Cleanup using Azure Developer CLI (preferred method)
cleanup_with_azd() {
    echo -e "${YELLOW}🧹 Attempting cleanup with Azure Developer CLI...${NC}"
    
    if [ "$AZD_AVAILABLE" = true ] && [ -f "azure.yaml" ]; then
        echo -e "${YELLOW}Found azure.yaml configuration file${NC}"
        
        # Check if azd environment exists
        if azd env list 2>/dev/null | grep -q "$APP_NAME"; then
            echo -e "${YELLOW}📋 Azure Developer CLI environment found${NC}"
            
            # Ask for confirmation
            echo -e "${RED}⚠️  This will destroy all resources created by azd for environment: $APP_NAME${NC}"
            read -p "Are you sure you want to continue? (y/N): " -n 1 -r
            echo
            
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}🗑️  Destroying infrastructure with azd...${NC}"
                
                # Set the environment
                azd env select "$APP_NAME" 2>/dev/null || true
                
                # Run azd down to destroy infrastructure
                if azd down --force --purge; then
                    echo -e "${GREEN}✅ Successfully destroyed infrastructure with azd${NC}"
                    
                    # Clean up azd environment
                    azd env select "$APP_NAME" 2>/dev/null && azd env delete "$APP_NAME" --force 2>/dev/null || true
                    
                    echo -e "${GREEN}🎉 Cleanup completed successfully with Azure Developer CLI${NC}"
                    return 0
                else
                    echo -e "${YELLOW}⚠️  azd down failed, falling back to manual cleanup${NC}"
                fi
            else
                echo -e "${YELLOW}Operation cancelled${NC}"
                exit 0
            fi
        else
            echo -e "${YELLOW}⚠️  No azd environment found, using manual cleanup${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Azure Developer CLI not available or no azure.yaml found, using manual cleanup${NC}"
    fi
    
    return 1
}

# Manual cleanup using Azure CLI
cleanup_manually() {
    echo -e "${YELLOW}🔧 Performing manual cleanup with Azure CLI...${NC}"
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        echo -e "${YELLOW}⚠️  Resource group '$RESOURCE_GROUP' not found${NC}"
        echo -e "${BLUE}ℹ️  No resources to clean up${NC}"
        return 0
    fi
    
    # List all resources in the resource group
    echo -e "${YELLOW}📋 Listing resources in resource group: $RESOURCE_GROUP${NC}"
    RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name,Type:type,Id:id}" -o table)
    
    if [ -z "$RESOURCES" ] || echo "$RESOURCES" | grep -q "No resources found"; then
        echo -e "${YELLOW}⚠️  No resources found in resource group${NC}"
        
        # Ask if user wants to delete the empty resource group
        read -p "Delete the empty resource group '$RESOURCE_GROUP'? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            az group delete --name "$RESOURCE_GROUP" --yes --no-wait
            echo -e "${GREEN}✅ Empty resource group deletion initiated${NC}"
        fi
        return 0
    fi
    
    echo -e "${BLUE}Resources found:${NC}"
    echo "$RESOURCES"
    echo ""
    
    # Confirm deletion
    echo -e "${RED}⚠️  This will delete ALL resources in the resource group: $RESOURCE_GROUP${NC}"
    echo -e "${RED}This action cannot be undone!${NC}"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Operation cancelled${NC}"
        exit 0
    fi
    
    # Delete specific resources in order (to handle dependencies)
    echo -e "${YELLOW}🗑️  Deleting resources in dependency order...${NC}"
    
    # 1. Delete App Service (Web Apps)
    echo -e "${YELLOW}Deleting App Services...${NC}"
    APP_SERVICES=$(az webapp list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || true)
    for app in $APP_SERVICES; do
        if [ ! -z "$app" ]; then
            echo -e "${BLUE}  Deleting App Service: $app${NC}"
            az webapp delete --name "$app" --resource-group "$RESOURCE_GROUP" &
        fi
    done
    wait
    
    # 2. Delete PostgreSQL Databases (before servers)
    echo -e "${YELLOW}Deleting PostgreSQL Databases...${NC}"
    PSQL_SERVERS=$(az postgres flexible-server list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || true)
    for server in $PSQL_SERVERS; do
        if [ ! -z "$server" ]; then
            DATABASES=$(az postgres flexible-server db list --resource-group "$RESOURCE_GROUP" --server-name "$server" --query "[].name" -o tsv 2>/dev/null || true)
            for db in $DATABASES; do
                if [ ! -z "$db" ] && [ "$db" != "postgres" ] && [ "$db" != "azure_maintenance" ]; then
                    echo -e "${BLUE}  Deleting Database: $db from server $server${NC}"
                    az postgres flexible-server db delete --resource-group "$RESOURCE_GROUP" --server-name "$server" --database-name "$db" --yes &
                fi
            done
        fi
    done
    wait
    
    # 3. Delete PostgreSQL Servers
    echo -e "${YELLOW}Deleting PostgreSQL Servers...${NC}"
    for server in $PSQL_SERVERS; do
        if [ ! -z "$server" ]; then
            echo -e "${BLUE}  Deleting PostgreSQL Server: $server${NC}"
            az postgres flexible-server delete --name "$server" --resource-group "$RESOURCE_GROUP" --yes &
        fi
    done
    wait
    
    # 4. Delete App Service Plans
    echo -e "${YELLOW}Deleting App Service Plans...${NC}"
    SERVICE_PLANS=$(az appservice plan list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || true)
    for plan in $SERVICE_PLANS; do
        if [ ! -z "$plan" ]; then
            echo -e "${BLUE}  Deleting App Service Plan: $plan${NC}"
            az appservice plan delete --name "$plan" --resource-group "$RESOURCE_GROUP" --yes &
        fi
    done
    wait
    
    # 5. Delete any remaining resources
    echo -e "${YELLOW}Deleting any remaining resources...${NC}"
    REMAINING_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].id" -o tsv 2>/dev/null || true)
    for resource_id in $REMAINING_RESOURCES; do
        if [ ! -z "$resource_id" ]; then
            echo -e "${BLUE}  Deleting resource: $resource_id${NC}"
            az resource delete --ids "$resource_id" &
        fi
    done
    wait
    
    # 6. Delete the resource group
    echo -e "${YELLOW}Deleting resource group: $RESOURCE_GROUP${NC}"
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
    
    echo -e "${GREEN}✅ Resource deletion initiated. Some resources may take several minutes to be fully deleted.${NC}"
}

# Clean up local azd files
cleanup_local_files() {
    echo -e "${YELLOW}🧹 Cleaning up local Azure Developer CLI files...${NC}"
    
    # Ask if user wants to clean up local files
    read -p "Do you want to clean up local azd configuration files? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Remove azd environment directory
        if [ -d ".azure" ]; then
            rm -rf ".azure"
            echo -e "${GREEN}✅ Removed .azure directory${NC}"
        fi
        
        # Remove azure.yaml if it exists
        if [ -f "azure.yaml" ]; then
            read -p "Remove azure.yaml file? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -f "azure.yaml"
                echo -e "${GREEN}✅ Removed azure.yaml${NC}"
            fi
        fi
        
        # Remove infra directory if it exists
        if [ -d "infra" ]; then
            read -p "Remove infra directory (contains Terraform files)? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -rf "infra"
                echo -e "${GREEN}✅ Removed infra directory${NC}"
            fi
        fi
        
        # Remove Azure-specific files created by deploy.sh
        local azure_files=("startup.sh" ".deployment")
        for file in "${azure_files[@]}"; do
            if [ -f "$file" ]; then
                read -p "Remove $file? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    rm -f "$file"
                    echo -e "${GREEN}✅ Removed $file${NC}"
                fi
            fi
        done
        
        echo -e "${GREEN}✅ Local cleanup completed${NC}"
    fi
}

# Check final status
check_cleanup_status() {
    echo -e "${YELLOW}🔍 Checking cleanup status...${NC}"
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        echo -e "${YELLOW}⚠️  Resource group still exists (deletion may be in progress)${NC}"
        
        # List any remaining resources
        REMAINING=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name,Type:type}" -o table 2>/dev/null || true)
        if [ ! -z "$REMAINING" ] && ! echo "$REMAINING" | grep -q "No resources found"; then
            echo -e "${YELLOW}Remaining resources:${NC}"
            echo "$REMAINING"
            echo -e "${BLUE}ℹ️  These resources may still be deleting. Check the Azure portal for status.${NC}"
        fi
    else
        echo -e "${GREEN}✅ Resource group has been successfully deleted${NC}"
    fi
}

# Main execution
main() {
    echo -e "${YELLOW}Starting cleanup process...${NC}"
    echo ""
    
    check_dependencies
    check_azure_login
    
    # Try azd cleanup first, fall back to manual if it fails
    if ! cleanup_with_azd; then
        cleanup_manually
    fi
    
    cleanup_local_files
    check_cleanup_status
    
    echo ""
    echo -e "${GREEN}🎉 Cleanup process completed!${NC}"
    echo -e "${BLUE}ℹ️  Note: Some resources may take additional time to be fully deleted from Azure.${NC}"
}

# Run main function
main "$@"



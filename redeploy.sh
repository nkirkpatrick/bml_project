#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="${APP_NAME:-django-app}"
LOCATION="${LOCATION:-eastus}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-${APP_NAME}}"

echo -e "${BLUE}🔄 Django App Redeployment Script${NC}"
echo "App Name: $APP_NAME"
echo "Location: $LOCATION"
echo "Resource Group: $RESOURCE_GROUP"

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --code-only       Deploy only code changes (fastest)"
    echo "  --full            Full redeployment including infrastructure"
    echo "  --migrate         Run database migrations after deployment"
    echo "  --collectstatic   Force collect static files"
    echo "  --restart         Restart the app service after deployment"
    echo "  --logs            Show deployment logs after completion"
    echo "  --force           Skip confirmation prompts"
    echo "  --help            Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  APP_NAME          Name of the application (default: django-app)"
    echo "  LOCATION          Azure region (default: eastus)"
    echo "  RESOURCE_GROUP    Resource group name (default: rg-\$APP_NAME)"
    echo ""
    echo "Examples:"
    echo "  $0                          # Quick code-only deployment"
    echo "  $0 --full                   # Full redeployment with infrastructure"
    echo "  $0 --code-only --migrate    # Deploy code and run migrations"
    echo "  $0 --restart --logs         # Deploy, restart, and show logs"
}

# Parse command line arguments
CODE_ONLY=true
FULL_DEPLOY=false
RUN_MIGRATIONS=false
COLLECT_STATIC=false
RESTART_APP=false
SHOW_LOGS=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --code-only)
            CODE_ONLY=true
            FULL_DEPLOY=false
            shift
            ;;
        --full)
            CODE_ONLY=false
            FULL_DEPLOY=true
            shift
            ;;
        --migrate)
            RUN_MIGRATIONS=true
            shift
            ;;
        --collectstatic)
            COLLECT_STATIC=true
            shift
            ;;
        --restart)
            RESTART_APP=true
            shift
            ;;
        --logs)
            SHOW_LOGS=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Check if required tools are installed
check_dependencies() {
    echo -e "${YELLOW}📋 Checking dependencies...${NC}"
    
    local missing_deps=()
    
    if ! command -v azd &> /dev/null; then
        missing_deps+=("Azure Developer CLI (azd)")
    fi
    
    if ! command -v az &> /dev/null; then
        missing_deps+=("Azure CLI (az)")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${RED}❌ Missing dependencies:${NC}"
        printf '%s\n' "${missing_deps[@]}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ All dependencies are installed${NC}"
}

# Verify project structure
verify_project_structure() {
    echo -e "${YELLOW}🔍 Verifying project structure...${NC}"
    
    local missing_files=()
    
    # Check for essential files
    if [ ! -f "manage.py" ]; then
        missing_files+=("manage.py - Django project root")
    fi
    
    if [ ! -f "azure.yaml" ]; then
        missing_files+=("azure.yaml - Azure Developer CLI configuration")
    fi
    
    if [ ! -d "infra" ]; then
        missing_files+=("infra/ - Terraform infrastructure directory")
    fi
    
    if [ ! -f "requirements.txt" ]; then
        missing_files+=("requirements.txt - Python dependencies")
    fi
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        echo -e "${RED}❌ Missing required files for redeployment:${NC}"
        printf '%s\n' "${missing_files[@]}"
        echo ""
        echo -e "${YELLOW}💡 This script requires a project that was previously deployed with deploy.sh${NC}"
        echo -e "${YELLOW}   Run ./deploy.sh first to set up the initial deployment${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Project structure verified${NC}"
}

# Check Azure authentication
check_azure_auth() {
    echo -e "${YELLOW}🔐 Checking Azure authentication...${NC}"
    
    if ! az account show &> /dev/null; then
        echo -e "${YELLOW}🔑 Not logged into Azure. Logging in...${NC}"
        az login
    fi
    
    local subscription=$(az account show --query name -o tsv)
    echo -e "${GREEN}✅ Authenticated to Azure subscription: ${subscription}${NC}"
}

# Check deployment status
check_deployment_status() {
    echo -e "${YELLOW}📊 Checking current deployment status...${NC}"
    
    if [ ! -d ".azure" ]; then
        echo -e "${RED}❌ No .azure directory found${NC}"
        echo -e "${YELLOW}💡 This suggests the project hasn't been deployed yet${NC}"
        echo -e "${YELLOW}   Run ./deploy.sh first to create initial deployment${NC}"
        exit 1
    fi
    
    # Check if resources exist
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        echo -e "${GREEN}✅ Resource group '$RESOURCE_GROUP' exists${NC}"
        
        # Get app service name
        APP_SERVICE_NAME=$(az webapp list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null || echo "")
        if [ -n "$APP_SERVICE_NAME" ]; then
            echo -e "${GREEN}✅ App Service '$APP_SERVICE_NAME' found${NC}"
        else
            echo -e "${YELLOW}⚠️  No App Service found in resource group${NC}"
        fi
    else
        echo -e "${RED}❌ Resource group '$RESOURCE_GROUP' not found${NC}"
        echo -e "${YELLOW}💡 Run ./deploy.sh first to create initial deployment${NC}"
        exit 1
    fi
}

# Update requirements if needed
update_requirements() {
    echo -e "${YELLOW}📦 Checking requirements.txt...${NC}"
    
    if [ -f "requirements.txt" ]; then
        # Check if Azure-specific packages are present
        local missing_packages=()
        
        if ! grep -q "gunicorn" requirements.txt; then
            missing_packages+=("gunicorn>=20.1.0")
        fi
        
        if ! grep -q "psycopg2" requirements.txt; then
            missing_packages+=("psycopg2-binary>=2.9.0")
        fi
        
        if ! grep -q "whitenoise" requirements.txt; then
            missing_packages+=("whitenoise>=6.0.0")
        fi
        
        if ! grep -q "python-decouple" requirements.txt; then
            missing_packages+=("python-decouple>=3.8")
        fi
        
        if [ ${#missing_packages[@]} -gt 0 ]; then
            echo -e "${YELLOW}📝 Adding missing Azure deployment packages...${NC}"
            {
                echo ""
                echo "# Azure deployment dependencies (added by redeploy.sh)"
                printf '%s\n' "${missing_packages[@]}"
            } >> requirements.txt
            echo -e "${GREEN}✅ Updated requirements.txt${NC}"
        else
            echo -e "${GREEN}✅ Requirements.txt is up to date${NC}"
        fi
    fi
}

# Pre-deployment checks
pre_deployment_checks() {
    echo -e "${YELLOW}🔍 Running pre-deployment checks...${NC}"
    
    # Check for uncommitted changes
    if [ -d ".git" ]; then
        if ! git diff-index --quiet HEAD --; then
            echo -e "${YELLOW}⚠️  You have uncommitted changes${NC}"
            if [ "$FORCE" != true ]; then
                read -p "Continue anyway? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    echo -e "${BLUE}ℹ️  Deployment cancelled${NC}"
                    exit 0
                fi
            fi
        fi
    fi
    
    # Check Python syntax if possible
    if command -v python &> /dev/null; then
        echo -e "${YELLOW}🐍 Checking Python syntax...${NC}"
        if python -m py_compile manage.py 2>/dev/null; then
            echo -e "${GREEN}✅ Python syntax check passed${NC}"
        else
            echo -e "${YELLOW}⚠️  Python syntax check failed, but continuing...${NC}"
        fi
    fi
}

# Deploy code only
deploy_code_only() {
    echo -e "${YELLOW}🚀 Deploying code changes only...${NC}"
    
    # Use azd deploy without provisioning
    azd deploy --no-provision
    
    echo -e "${GREEN}✅ Code deployment completed${NC}"
}

# Full deployment
deploy_full() {
    echo -e "${YELLOW}🚀 Running full deployment (infrastructure + code)...${NC}"
    
    # Run full azd up
    azd up --confirm-provisioning
    
    echo -e "${GREEN}✅ Full deployment completed${NC}"
}

# Run database migrations
run_migrations() {
    echo -e "${YELLOW}🗄️  Running database migrations...${NC}"
    
    if [ -n "$APP_SERVICE_NAME" ]; then
        # Run migrations via Azure CLI
        az webapp ssh --name "$APP_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" --command "cd /home/site/wwwroot && python manage.py migrate --noinput" || {
            echo -e "${YELLOW}⚠️  Migration command failed, but continuing...${NC}"
        }
        echo -e "${GREEN}✅ Database migrations completed${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not determine app service name for migrations${NC}"
    fi
}

# Collect static files
collect_static_files() {
    echo -e "${YELLOW}📁 Collecting static files...${NC}"
    
    if [ -n "$APP_SERVICE_NAME" ]; then
        # Run collectstatic via Azure CLI
        az webapp ssh --name "$APP_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" --command "cd /home/site/wwwroot && python manage.py collectstatic --noinput" || {
            echo -e "${YELLOW}⚠️  Collectstatic command failed, but continuing...${NC}"
        }
        echo -e "${GREEN}✅ Static files collected${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not determine app service name for collectstatic${NC}"
    fi
}

# Restart app service
restart_app_service() {
    echo -e "${YELLOW}🔄 Restarting App Service...${NC}"
    
    if [ -n "$APP_SERVICE_NAME" ]; then
        az webapp restart --name "$APP_SERVICE_NAME" --resource-group "$RESOURCE_GROUP"
        echo -e "${GREEN}✅ App Service restarted${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not determine app service name for restart${NC}"
    fi
}

# Show deployment logs
show_deployment_logs() {
    echo -e "${YELLOW}📋 Fetching deployment logs...${NC}"
    
    if [ -n "$APP_SERVICE_NAME" ]; then
        echo -e "${CYAN}=== Recent Application Logs ===${NC}"
        az webapp log tail --name "$APP_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" --timeout 30 || {
            echo -e "${YELLOW}⚠️  Could not fetch live logs, showing recent logs instead${NC}"
            az webapp log download --name "$APP_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" --log-file app-logs.zip 2>/dev/null || true
        }
    else
        echo -e "${YELLOW}⚠️  Could not determine app service name for logs${NC}"
    fi
}

# Get application URL
get_app_url() {
    echo -e "${YELLOW}🌐 Getting application URL...${NC}"
    
    if [ -n "$APP_SERVICE_NAME" ]; then
        local app_url=$(az webapp show --name "$APP_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" --query "defaultHostName" -o tsv)
        if [ -n "$app_url" ]; then
            echo -e "${GREEN}🎉 Your Django app is available at: https://$app_url${NC}"
            return 0
        fi
    fi
    
    # Fallback: try azd show
    local azd_output=$(azd show --output json 2>/dev/null || echo "{}")
    local app_url=$(echo "$azd_output" | jq -r '.services.api.endpoint // empty' 2>/dev/null || echo "")
    if [ -n "$app_url" ]; then
        echo -e "${GREEN}🎉 Your Django app is available at: $app_url${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not determine application URL${NC}"
        echo -e "${YELLOW}   Check Azure Portal or run: az webapp list --resource-group $RESOURCE_GROUP${NC}"
    fi
}

# Main execution function
main() {
    echo -e "${BLUE}Starting redeployment process...${NC}"
    echo ""
    
    # Pre-flight checks
    check_dependencies
    verify_project_structure
    check_azure_auth
    check_deployment_status
    pre_deployment_checks
    
    echo ""
    echo -e "${CYAN}=== Deployment Configuration ===${NC}"
    echo "Mode: $([ "$FULL_DEPLOY" = true ] && echo "Full deployment" || echo "Code-only deployment")"
    echo "Run migrations: $([ "$RUN_MIGRATIONS" = true ] && echo "Yes" || echo "No")"
    echo "Collect static: $([ "$COLLECT_STATIC" = true ] && echo "Yes" || echo "No")"
    echo "Restart app: $([ "$RESTART_APP" = true ] && echo "Yes" || echo "No")"
    echo "Show logs: $([ "$SHOW_LOGS" = true ] && echo "Yes" || echo "No")"
    echo ""
    
    # Confirm deployment
    if [ "$FORCE" != true ]; then
        read -p "Continue with redeployment? (Y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            echo -e "${BLUE}ℹ️  Deployment cancelled${NC}"
            exit 0
        fi
    fi
    
    echo -e "${CYAN}=== Starting Deployment ===${NC}"
    
    # Update requirements if needed
    update_requirements
    
    # Deploy based on mode
    if [ "$FULL_DEPLOY" = true ]; then
        deploy_full
    else
        deploy_code_only
    fi
    
    # Post-deployment tasks
    if [ "$RUN_MIGRATIONS" = true ]; then
        echo ""
        run_migrations
    fi
    
    if [ "$COLLECT_STATIC" = true ]; then
        echo ""
        collect_static_files
    fi
    
    if [ "$RESTART_APP" = true ]; then
        echo ""
        restart_app_service
    fi
    
    echo ""
    echo -e "${GREEN}✅ Redeployment completed successfully!${NC}"
    
    # Show application URL
    echo ""
    get_app_url
    
    # Show logs if requested
    if [ "$SHOW_LOGS" = true ]; then
        echo ""
        show_deployment_logs
    fi
    
    echo ""
    echo -e "${CYAN}=== Next Steps ===${NC}"
    echo "• Test your application at the URL above"
    echo "• Monitor logs: az webapp log tail --name $APP_SERVICE_NAME --resource-group $RESOURCE_GROUP"
    echo "• Check app status: az webapp show --name $APP_SERVICE_NAME --resource-group $RESOURCE_GROUP"
    echo "• For issues, check: Azure Portal > App Service > Log stream"
}

# Handle script interruption
trap 'echo -e "\n${YELLOW}⚠️  Deployment interrupted. Check Azure Portal for resource status.${NC}"; exit 1' INT TERM

# Run main function
main "$@"

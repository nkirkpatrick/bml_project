I've created a comprehensive redeploy.sh script that handles redeployment of Django apps previously deployed with the deploy.sh script. Here are the key features:
🚀 Key Features
Deployment Modes:

--code-only (default): Fast deployment of just code changes
--full: Complete redeployment including infrastructure updates

Additional Options:

--migrate: Run database migrations after deployment
--collectstatic: Force collection of static files
--restart: Restart the App Service after deployment
--logs: Show deployment logs after completion
--force: Skip confirmation prompts

📋 Usage Examples
bash# Make script executable
chmod +x redeploy.sh

# Quick code-only deployment (default)
./redeploy.sh

# Full redeployment with infrastructure
./redeploy.sh --full

# Deploy code and run migrations
./redeploy.sh --code-only --migrate

# Deploy, restart app, and show logs
./redeploy.sh --restart --logs

# Full deployment with all post-deployment tasks
./redeploy.sh --full --migrate --collectstatic --restart --logs

# Force deployment without confirmations
./redeploy.sh --force
🔍 Pre-Flight Checks
The script performs comprehensive checks before deployment:

Dependencies: Verifies azd and az CLI are installed
Project Structure: Ensures required files exist (manage.py, azure.yaml, infra/, etc.)
Azure Authentication: Checks/prompts for Azure login
Deployment Status: Verifies existing deployment exists
Requirements: Updates requirements.txt with missing Azure packages
Code Quality: Basic Python syntax checking

⚡ Smart Features
Automatic Detection:

Finds your App Service name automatically
Detects resource group and configuration
Identifies missing Azure deployment dependencies

Safety Features:

Warns about uncommitted Git changes
Confirms deployment before proceeding
Handles errors gracefully
Provides helpful error messages

Post-Deployment:

Shows application URL
Provides monitoring commands
Suggests next steps

🎯 Deployment Strategies
Code-Only (Fast - Default):
bash./redeploy.sh
# Perfect for: Bug fixes, feature updates, Django code changes
# Time: ~2-3 minutes
Full Deployment:
bash./redeploy.sh --full
# Perfect for: Infrastructure changes, scaling, configuration updates
# Time: ~5-10 minutes
Database Updates:
bash./redeploy.sh --migrate
# Perfect for: Model changes, schema updates
🔧 Configuration
Set environment variables for different projects:
bashexport APP_NAME="my-production-app"
export LOCATION="westus2"
export RESOURCE_GROUP="rg-production"
./redeploy.sh
📊 What It Checks
The script verifies your project has:

✅ manage.py (Django project)
✅ azure.yaml (Azure Developer CLI config)
✅ infra/ directory (Terraform files)
✅ requirements.txt (Python dependencies)
✅ Existing Azure resources
✅ Valid Azure authentication

🆚 Redeploy vs Deploy vs Cleanup
ScriptPurposeWhen to Usedeploy.shInitial deploymentFirst time setupredeploy.shUpdate existing deploymentCode changes, updatescleanup.shRemove and recreateMajor issues, fresh start
💡 Pro Tips

Quick Updates: Use default ./redeploy.sh for most code changes
Database Changes: Always use --migrate when you've changed models
Static Files: Use --collectstatic if you've updated CSS/JS/images
Troubleshooting: Use --logs to see what's happening
Production: Use --force in CI/CD pipelines

The script is designed to be fast, safe, and informative - perfect for iterative development and production updates!RetryClaude does not have the ability to run the code it generates yet.Claude can make mistakes. Please double-check responses. Sonnet 4
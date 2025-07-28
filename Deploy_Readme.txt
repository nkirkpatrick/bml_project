# Using deploy.sh with Your Existing Django Project

## 🎯 **Overview**

The updated `deploy.sh` script now works with your existing Django project instead of creating a new one. Here's how to use it with your local Django application.

## 📋 **Prerequisites**

1. **Your Django project should have the standard structure:**
   ```
   your-django-project/
   ├── manage.py
   ├── your_project_name/
   │   ├── __init__.py
   │   ├── settings.py
   │   ├── urls.py
   │   └── wsgi.py
   ├── your_apps/
   └── (other files)
   ```

2. **Required tools installed:**
   - Azure CLI (`az`)
   - Azure Developer CLI (`azd`)
   - Terraform
   - Python 3.11+

## 🚀 **Step-by-Step Usage**

### 1. **Navigate to Your Django Project Root**
```bash
cd /path/to/your/django/project
# Make sure you can see manage.py in this directory
ls manage.py
```

### 2. **Download the Deploy Script**
Place the `deploy.sh` script in your Django project root directory:
```bash
# Your project structure should now look like:
your-django-project/
├── deploy.sh          # <- New deployment script
├── manage.py          # <- Your existing Django project
├── your_project_name/
└── ...
```

### 3. **Set Environment Variables (Optional)**
```bash
export APP_NAME="my-awesome-app"
export LOCATION="westus2"
export RESOURCE_GROUP="rg-my-awesome-app"
```

### 4. **Run the Deployment**
```bash
chmod +x deploy.sh
./deploy.sh
```

## 🔧 **What the Script Does to Your Project**

### **Files Created/Modified:**

1. **`requirements.txt`** - Updated with Azure-specific dependencies:
   - Your existing requirements are preserved
   - Adds: `gunicorn`, `psycopg2-binary`, `python-decouple`, `whitenoise`
   - Creates backup: `requirements.txt.backup`

2. **`your_project/production_settings.py`** - New production settings file:
   - Imports from your existing `settings.py`
   - Configures PostgreSQL database
   - Sets up static files with WhiteNoise
   - Enables security settings

3. **`.env`** - Environment variables for local development (if doesn't exist)

4. **`startup.sh`** - Azure App Service startup script

5. **`.deployment`** - Azure deployment configuration

6. **Infrastructure files:**
   - `azure.yaml` - Azure Developer CLI configuration
   - `infra/` directory with Terraform files

### **No Changes Made To:**
- Your existing `settings.py`
- Your Django apps
- Your models, views, templates
- Any existing code

## ⚙️ **Configuration Details**

### **Database Configuration**
The script creates a PostgreSQL database on Azure and configures your Django app to use it in production while keeping your local database unchanged.

### **Static Files**
WhiteNoise is configured to serve static files efficiently on Azure App Service.

### **Environment Variables**
The script uses `django-decouple` to manage environment-specific settings:
- **Local development**: Uses `.env` file
- **Production**: Uses Azure App Service configuration

## 🔍 **Auto-Detection Features**

The script automatically detects:
1. **Django project name** - Scans for `settings.py` files
2. **Project structure** - Validates it's a Django project
3. **Dependencies** - Preserves existing requirements

## 🐛 **Troubleshooting**

### **"No manage.py found" Error**
- Ensure you're in your Django project root directory
- The directory containing `manage.py` is where you should run the script

### **"Could not detect Django project name" Error**
- Manually set the project name:
  ```bash
  export DJANGO_PROJECT_NAME="your_actual_project_name"
  ./deploy.sh
  ```

### **Database Connection Issues**
- Check that your local Django project doesn't have conflicting database settings
- Verify the production settings file was created correctly

### **Import Errors in Production**
- Make sure all your app dependencies are in `requirements.txt`
- Check the Azure App Service logs for specific error messages

## 📁 **Project Structure After Deployment**

```
your-django-project/
├── deploy.sh
├── cleanup.sh
├── manage.py
├── your_project_name/
│   ├── settings.py              # Your original settings (unchanged)
│   ├── production_settings.py   # New production settings
│   └── ...
├── requirements.txt             # Updated with Azure dependencies
├── requirements.txt.backup      # Your original requirements
├── .env                         # Local development environment
├── startup.sh                   # Azure startup script
├── .deployment                  # Azure deployment config
├── azure.yaml                   # Azure Developer CLI config
└── infra/                       # Terraform infrastructure
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── terraform.tfv
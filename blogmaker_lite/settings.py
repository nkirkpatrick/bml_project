import os
from pathlib import Path

# Build paths inside the project like this: BASE_DIR / 'subdir'.

BASE_DIR = Path(__file__).resolve().parent.parent

# Azure App Service Hostname, Custom Domain and localhost

ALLOWED_HOSTS = ['bml-dev-z6bzyuhskliuu.azurewebsites.net','nkirkpatrick-django.com','127.0.0.1']

ROOT_URLCONF="blogmaker_lite.urls"

DEBUG=True

SECRET_KEY="my-secret-key"

TEMPLATES=[
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [Path(__file__).parent / "templates"],
        "APP_DIRS": True,
        'OPTIONS':{
            'context_processors':[
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages'
            ]
        }
    }
]

INSTALLED_APPS=[
    "blogs",
    "accounts",
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.common.CommonMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',
]

# Use an environment variable to determine environment, USE_POSTGRES set to 'True' for Azure App Service
# and 'False' for local development. Default is 'False'.

USE_POSTGRES = os.getenv('USE_POSTGRES', 'False').lower() == 'true'

if USE_POSTGRES:
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.postgresql',
            'NAME': os.getenv('AZURE_POSTGRESQL_NAME'),
            'USER': os.getenv('AZURE_POSTGRESQL_USER'),
            'PASSWORD': os.getenv('AZURE_POSTGRESQL_PASSWORD'),
            'HOST': os.getenv('AZURE_POSTGRESQL_HOST'),
            'PORT': os.getenv('AZURE_POSTGRESQL_PORT', '5432'),
        }
    }
else:
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.sqlite3',
            'NAME': BASE_DIR / 'db.sqlite3',
        }
    }


# Disable Redis cache for local development and Azure App Service - Save Costs

# CACHES = {
#         "default": {  
#             "BACKEND": "django_redis.cache.RedisCache",
#             "LOCATION": os.environ.get('AZURE_REDIS_CONNECTIONSTRING'),
#             "OPTIONS": {
#                 "CLIENT_CLASS": "django_redis.client.DefaultClient",
#                 "COMPRESSOR": "django_redis.compressors.zlib.ZlibCompressor",
#         },
#     }
# }

CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
        "LOCATION": "unique-snowflake",
    }
}

DEFAULT_AUTO_FIELD="django.db.models.BigAutoField"

# Static files (CSS, JavaScript, Images), USE_POSTGRES set to 'True' for Azure App Service
# and 'False' for local development.

if USE_POSTGRES:
    # Azure App Service static files settings
    STATIC_URL = '/static/'
    STATIC_ROOT = os.path.join(BASE_DIR, 'staticfiles')
    STATICFILES_DIRS = [
        os.path.join(BASE_DIR, 'static'),
    ]
    STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'
else:
    # Local development static files settings
    STATIC_URL = 'static/'
    STATIC_ROOT = "staticfiles/"
    STATICFILES_DIRS = [
        "css",
    ] 
   
LOGIN_REDIRECT_URL = "blogs:index"
LOGOUT_REDIRECT_URL = "blogs:index"

# Security settings for production
CSRF_COOKIE_SECURE = True
SESSION_COOKIE_SECURE = True
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')








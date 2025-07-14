import os

import django
from django.core.management import call_command

# Load settings

os.environ["DJANGO_SETTINGS_MODULE"] = "blogmaker_lite.settings"
django.setup()

# Flush current data

call_command("flush", "--noinput")
print("Flushed existing db.")

# Create a superuser

os.environ["DJANGO_SUPERUSER_PASSWORD"] = "admin"

cmd = "createsuperuser --username admin"
cmd += " --email norbert_kirkpatrick@yahoo.com"
cmd += " --noinput"

cmd_parts = cmd.split()
call_command(*cmd_parts)

# Create sample blogs

from model_factories import BlogFactory, BlogPostFactory

for _ in range(10):
    BlogFactory.create()

for _ in range(100):
    BlogPostFactory.create()








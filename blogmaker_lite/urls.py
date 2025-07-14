from django.urls import path, include
from django.contrib import admin

from blogs import views

urlpatterns = [
    path("admin/", admin.site.urls),
    path("accounts/", include("accounts.urls")),
    path("", include("blogs.urls")),
]


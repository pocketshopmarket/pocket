from django.urls import path
from . import views

app_name = 'portal'

urlpatterns = [
    path('', views.index, name='index'),
    path('terms/', views.terms, name='terms'),
    path('privacy/', views.privacy, name='privacy'),
    path('manual/', views.manual, name='manual'),
    path('sitemap.xml', views.sitemap, name='sitemap'),
    path('robots.txt', views.robots, name='robots'),
]

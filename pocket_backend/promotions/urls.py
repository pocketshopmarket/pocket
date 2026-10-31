from django.urls import path

from . import views

app_name = 'promotions'

urlpatterns = [
    path('partners/', views.landing, name='landing'),
    path('partners/rules/', views.rules, name='rules'),
    path('partners/invite/<str:token>/', views.accept_invite, name='accept-invite'),
    path('partners/p/<str:token>/', views.partner_page, name='partner-page'),
    path('r/<str:code>/', views.share, name='share'),
]

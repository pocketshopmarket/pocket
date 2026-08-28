from django.urls import path

from .views import PartnerProductUpsertView

app_name = 'partner_api'

urlpatterns = [
    path('products/', PartnerProductUpsertView.as_view(), name='partner-product-upsert'),
]

from django.urls import path
from .views import EarningsSummaryView, InitiatePaymentView, PawaPayWebhookView, PaymentStatusView, RequestPayoutView

urlpatterns = [
    path('initiate/', InitiatePaymentView.as_view(), name='initiate-payment'),
    path('webhook/', PawaPayWebhookView.as_view(), name='pawapay-webhook'),
    path('status/', PaymentStatusView.as_view(), name='payment-status'),
    path('earnings/summary/', EarningsSummaryView.as_view(), name='earnings-summary'),
    path('payout/', RequestPayoutView.as_view(), name='request-payout'),
]


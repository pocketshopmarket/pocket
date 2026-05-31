from django.urls import path
from django.http import JsonResponse
from .views import EarningsSummaryView, InitiatePaymentView, PawaPayWebhookView, PaymentStatusView, RequestPayoutView


def _pawapay_ping(request):
    """Diagnose outbound connectivity to PawaPay from Railway."""
    import requests as req
    from django.conf import settings
    try:
        r = req.get(
            f"{settings.PAWAPAY_BASE_URL}/active-conf",
            headers={'Authorization': f'Bearer {settings.PAWAPAY_JWT_TOKEN}'},
            timeout=10,
        )
        return JsonResponse({'status': r.status_code, 'ok': r.status_code == 200, 'body': r.text[:200]})
    except Exception as e:
        return JsonResponse({'error': type(e).__name__, 'detail': str(e)}, status=500)


urlpatterns = [
    path('initiate/', InitiatePaymentView.as_view(), name='initiate-payment'),
    path('webhook/', PawaPayWebhookView.as_view(), name='pawapay-webhook'),
    path('status/', PaymentStatusView.as_view(), name='payment-status'),
    path('earnings/summary/', EarningsSummaryView.as_view(), name='earnings-summary'),
    path('payout/', RequestPayoutView.as_view(), name='request-payout'),
    path('ping/', _pawapay_ping, name='pawapay-ping'),
]


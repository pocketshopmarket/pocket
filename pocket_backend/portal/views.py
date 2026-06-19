from django.shortcuts import render
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import permissions
from .models import PlatformSettings


def index(request):
    return render(request, 'portal/index.html')

def terms(request):
    return render(request, 'portal/terms.html')

def privacy(request):
    return render(request, 'portal/privacy.html')


class PublicSettingsView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        s = PlatformSettings.get()
        return Response({
            'buyer_service_fee_rate': float(s.buyer_service_fee_rate),
            'seller_commission_rate': float(s.seller_commission_rate),
            'rider_commission_rate': float(s.rider_commission_rate),
            'payout_fee_rate': float(s.payout_fee_rate),
            'order_acceptance_timeout_minutes': s.order_acceptance_timeout_minutes,
            'payout_method': s.payout_method,
            'maintenance_mode': s.maintenance_mode,
            'maintenance_message': s.maintenance_message,
        })

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
            'order_acceptance_timeout_minutes': s.order_acceptance_timeout_minutes,
        })

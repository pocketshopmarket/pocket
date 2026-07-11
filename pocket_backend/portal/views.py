from datetime import datetime

from django.http import HttpResponse
from django.shortcuts import render
from rest_framework import permissions
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import PlatformSettings

_BASE_URL = 'https://mypocketshop.store'


def index(request):
    return render(request, 'portal/index.html')

def terms(request):
    return render(request, 'portal/terms.html')

def privacy(request):
    return render(request, 'portal/privacy.html')

def manual(request):
    return render(request, 'portal/manual.html')


def delete_account(request):
    """
    Public account-deletion request page (required by Google Play).
    Files the request as a staff notification; staff verify the owner's
    identity before deleting.
    """
    submitted = False
    error = ''
    if request.method == 'POST':
        phone = (request.POST.get('phone') or '').strip()
        reason = (request.POST.get('reason') or '').strip()[:500]
        try:
            from accounts.phone_utils import normalize_zambia_phone_to_e164
            phone_e164 = normalize_zambia_phone_to_e164(phone)
        except Exception:
            error = 'Please enter a valid Zambian mobile number (e.g. 097XXXXXXX).'
        if not error:
            from payments.staff_views import _notify_staff
            message = f'{phone_e164} requested account deletion via the website.'
            if reason:
                message += f' Reason: {reason}'
            _notify_staff(
                title='Account Deletion Request',
                message=message,
                data_payload={
                    'type': 'account_deletion_request',
                    'phone': phone_e164,
                },
            )
            submitted = True
    return render(
        request,
        'portal/delete_account.html',
        {'submitted': submitted, 'error': error},
    )


def sitemap(request):
    today = datetime.now().strftime('%Y-%m-%d')
    pages = [
        ('/', '1.0', 'weekly'),
        ('/terms/', '0.3', 'monthly'),
        ('/privacy/', '0.3', 'monthly'),
    ]
    urls = '\n'.join(
        f'  <url>\n'
        f'    <loc>{_BASE_URL}{loc}</loc>\n'
        f'    <lastmod>{today}</lastmod>\n'
        f'    <changefreq>{freq}</changefreq>\n'
        f'    <priority>{priority}</priority>\n'
        f'  </url>'
        for loc, priority, freq in pages
    )
    xml = f'<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n{urls}\n</urlset>'
    return HttpResponse(xml, content_type='application/xml')


def robots(request):
    txt = (
        'User-agent: *\n'
        'Allow: /\n'
        'Disallow: /admin/\n'
        'Disallow: /api/\n'
        'Disallow: /manual/\n'
        '\n'
        f'Sitemap: {_BASE_URL}/sitemap.xml\n'
    )
    return HttpResponse(txt, content_type='text/plain')


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

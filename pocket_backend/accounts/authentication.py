"""
Authentication for external/partner API callers — no self-service issuance,
no JWT. A staff member issues a SellerApiKey via Django admin and hands the
raw key to the partner out of band; this class resolves that key on every
request into the same request.user shape a JWT-authenticated seller would
have, so downstream code (IsApprovedSeller, serializers reading
request.user) needs no adaptation.

Wired in per-view (authentication_classes = [SellerApiKeyAuthentication] on
the specific partner view), matching the existing style of
payments.views.PawaPayWebhookView rather than touching the global
REST_FRAMEWORK['DEFAULT_AUTHENTICATION_CLASSES'] tuple.
"""
from django.utils import timezone
from rest_framework.authentication import BaseAuthentication
from rest_framework.exceptions import AuthenticationFailed

from .models import SellerApiKey


class SellerApiKeyAuthentication(BaseAuthentication):
    keyword = 'Api-Key'

    def authenticate(self, request):
        auth_header = request.headers.get('Authorization', '')
        if not auth_header:
            return None

        parts = auth_header.split(None, 1)
        if len(parts) != 2 or parts[0] != self.keyword:
            return None  # not our scheme — let other authenticators (or 401) handle it

        raw_key = parts[1].strip()
        if not raw_key:
            raise AuthenticationFailed('API key missing.')

        hashed = SellerApiKey.hash_key(raw_key)
        try:
            api_key = SellerApiKey.objects.select_related(
                'seller', 'seller__seller_profile',
            ).get(hashed_key=hashed)
        except SellerApiKey.DoesNotExist:
            raise AuthenticationFailed('Invalid API key.')

        if not api_key.is_active:
            raise AuthenticationFailed('This API key has been revoked.')

        seller = api_key.seller
        if seller.role != 'seller' or not seller.is_active or seller.is_deleted:
            raise AuthenticationFailed('This API key is no longer valid.')

        profile = getattr(seller, 'seller_profile', None)
        if not profile or not profile.can_sell:
            raise AuthenticationFailed('Seller approval is required.')

        SellerApiKey.objects.filter(pk=api_key.pk).update(last_used_at=timezone.now())
        request.seller_api_key = api_key  # read by PartnerAPIThrottle
        return (seller, None)

    def authenticate_header(self, request):
        # Without this, DRF's exception handler silently downgrades
        # AuthenticationFailed to a bare 403 instead of a proper 401.
        return self.keyword

from decimal import Decimal

from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from orders.models import Cart

from .services import PromoError, best_discount, find_partner_code, welcome_discount


def _cart_subtotal(user) -> Decimal:
    cart, _ = Cart.objects.get_or_create(user=user)
    return sum(
        (item.product.price * item.quantity for item in cart.items.select_related('product')),
        Decimal('0'),
    )


class CheckDiscountView(APIView):
    """Checkout preview: the discount this buyer gets on their current cart.

    Body: {"promo_code": "EASTER30"} (optional). Uses the server-side cart total,
    the same number order creation uses, so the preview always matches the charge.
    """

    permission_classes = [permissions.IsAuthenticated]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'promo_check'

    def post(self, request):
        subtotal = _cart_subtotal(request.user)
        code = str(request.data.get('promo_code') or '').strip()
        try:
            discount = best_discount(request.user, subtotal, code)
        except PromoError as exc:
            fallback = welcome_discount(request.user, subtotal)
            return Response(
                {'valid': False, 'error': str(exc), 'subtotal': str(subtotal), 'discount': fallback.as_dict()},
                status=status.HTTP_400_BAD_REQUEST,
            )
        note = ''
        if code and discount.kind == 'welcome':
            note = 'Your welcome discount is bigger, so we kept that one.'
        return Response({'valid': True, 'subtotal': str(subtotal), 'discount': discount.as_dict(), 'note': note})


class ReferralCodeView(APIView):
    """Sign-up helper: is this partner code real? Lets the app confirm before the OTP step."""

    permission_classes = [permissions.AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'referral_check'

    def get(self, request, code):
        partner = find_partner_code(code)
        if partner is None:
            return Response({'valid': False, 'error': "We couldn't find that code."}, status=status.HTTP_404_NOT_FOUND)
        return Response({'valid': True, 'code': partner.code, 'partner_name': partner.name})

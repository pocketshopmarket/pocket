from django.urls import path

from .api_views import CheckDiscountView, ReferralCodeView

urlpatterns = [
    path('check/', CheckDiscountView.as_view(), name='promo-check'),
    path('referral/<str:code>/', ReferralCodeView.as_view(), name='referral-check'),
]

from django.urls import path
from .views import (
    SendOTPView, VerifyOTPView, ProfileView,
    SellerApplicationView, DeliveryApplicationView, logout_view,
    LoginView, PasswordResetSendOTPView, PasswordResetConfirmView,
    ChangePasswordView,
    BuyerPaymentMethodsView, BuyerPaymentMethodDetailView,
    VerifyBuyerPaymentMethodView,
    SellerPayoutMethodsView, SellerPayoutMethodDetailView,
    VerifySellerPayoutMethodView,
)

urlpatterns = [
    path('login/', LoginView.as_view(), name='login'),
    path('send-otp/', SendOTPView.as_view(), name='send-otp'),
    path('verify-otp/', VerifyOTPView.as_view(), name='verify-otp'),
    path('password-reset/send-otp/', PasswordResetSendOTPView.as_view(), name='password-reset-send-otp'),
    path('password-reset/confirm/', PasswordResetConfirmView.as_view(), name='password-reset-confirm'),
    path('change-password/', ChangePasswordView.as_view(), name='change-password'),
    path('profile/', ProfileView.as_view(), name='profile'),
    path('seller-apply/', SellerApplicationView.as_view(), name='seller-apply'),
    path('delivery-apply/', DeliveryApplicationView.as_view(), name='delivery-apply'),
    path('buyer/payment-methods/', BuyerPaymentMethodsView.as_view(), name='buyer-payment-methods'),
    path(
        'buyer/payment-methods/<int:method_id>/',
        BuyerPaymentMethodDetailView.as_view(),
        name='buyer-payment-method-detail',
    ),
    path(
        'buyer/payment-methods/<int:method_id>/verify/',
        VerifyBuyerPaymentMethodView.as_view(),
        name='verify-buyer-payment-method',
    ),
    path(
        'seller/payout-methods/',
        SellerPayoutMethodsView.as_view(),
        name='seller-payout-methods',
    ),
    path(
        'seller/payout-methods/<int:method_id>/',
        SellerPayoutMethodDetailView.as_view(),
        name='seller-payout-method-detail',
    ),
    path(
        'seller/payout-methods/<int:method_id>/verify/',
        VerifySellerPayoutMethodView.as_view(),
        name='verify-seller-payout-method',
    ),
    path('logout/', logout_view, name='logout'),
]

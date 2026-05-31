from django.urls import path
from .views import (
    CartView,
    CartItemDetailView,
    CreateOrderView,
    OrderListView,
    OrderDetailView,
    UpdateOrderStatusView,
    BuyerCancelOrderView,
    SellerDashboardStatsView,
    OrderRatingListCreateView,
    RefundRequestCreateView,
    RefundRequestListView,
    RefundRequestRespondView,
)

urlpatterns = [
    # Cart endpoints
    path('cart/', CartView.as_view(), name='cart'),
    path('cart/<int:item_id>/', CartItemDetailView.as_view(), name='cart-item-detail'),

    # Order endpoints
    path('orders/create/', CreateOrderView.as_view(), name='create-order'),
    path('orders/', OrderListView.as_view(), name='order-list'),
    path('orders/<int:order_id>/', OrderDetailView.as_view(), name='order-detail'),
    path('orders/<int:order_id>/status/', UpdateOrderStatusView.as_view(), name='update-order-status'),
    path('orders/<int:order_id>/cancel/', BuyerCancelOrderView.as_view(), name='buyer-cancel-order'),
    path('orders/<int:order_id>/ratings/', OrderRatingListCreateView.as_view(), name='order-ratings'),
    path('orders/<int:order_id>/refund-request/', RefundRequestCreateView.as_view(), name='order-refund-request'),

    # Refund request list + respond
    path('refund-requests/', RefundRequestListView.as_view(), name='refund-request-list'),
    path('refund-requests/<int:pk>/respond/', RefundRequestRespondView.as_view(), name='refund-request-respond'),

    path(
        'seller/dashboard-stats/',
        SellerDashboardStatsView.as_view(),
        name='seller-dashboard-stats',
    ),
]


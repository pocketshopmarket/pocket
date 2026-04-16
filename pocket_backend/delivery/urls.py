from django.urls import path

from .views import (
    AddressAutocompleteView,
    AcceptDeliveryView,
    ActiveAssignmentView,
    AvailableOrdersView,
    DeliveryQuoteView,
    DeliveryOffersView,
    DeliveryStatsView,
    DeliveryZonesListView,
    GenerateHandoffTokenView,
    ReverseGeocodeView,
    TrackDeliveryView,
    UpdateDeliveryStatusView,
    UpdateLocationView,
    VerifyHandoffTokenView,
)

urlpatterns = [
    path('orders/available/', AvailableOrdersView.as_view(), name='available-orders'),
    path('orders/accept/', AcceptDeliveryView.as_view(), name='accept-delivery'),
    path('location/update/', UpdateLocationView.as_view(), name='update-location'),
    path(
        'assignment/<int:assignment_id>/status/',
        UpdateDeliveryStatusView.as_view(),
        name='update-delivery-status',
    ),
    path(
        'assignments/active/',
        ActiveAssignmentView.as_view(),
        name='active-assignment',
    ),
    path('offers/', DeliveryOffersView.as_view(), name='delivery-offers'),
    path(
        'assignment/<int:assignment_id>/handoff/token/',
        GenerateHandoffTokenView.as_view(),
        name='handoff-token-generate',
    ),
    path(
        'assignment/<int:assignment_id>/handoff/verify/',
        VerifyHandoffTokenView.as_view(),
        name='handoff-token-verify',
    ),
    path('track/<str:order_number>/', TrackDeliveryView.as_view(), name='track-delivery'),
    path('zones/', DeliveryZonesListView.as_view(), name='delivery-zones'),
    path('quote/', DeliveryQuoteView.as_view(), name='delivery-quote'),
    path('geocode/reverse/', ReverseGeocodeView.as_view(), name='reverse-geocode'),
    path('geocode/search/', AddressAutocompleteView.as_view(), name='address-autocomplete'),
    path('stats/', DeliveryStatsView.as_view(), name='delivery-stats'),
]

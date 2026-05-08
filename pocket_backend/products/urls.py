from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import ProductViewSet, CategoryViewSet, RecommendedProductsView, TrackInteractionView, PromoBannerListView

router = DefaultRouter()
router.register(r'', ProductViewSet, basename='product')

urlpatterns = [
    path('categories/', CategoryViewSet.as_view({'get': 'list'}), name='category-list'),
    path('categories/<int:pk>/', CategoryViewSet.as_view({'get': 'retrieve'}), name='category-detail'),
    path('recommended/', RecommendedProductsView.as_view(), name='recommended-products'),
    path('interact/', TrackInteractionView.as_view(), name='track-interaction'),
    path('banners/', PromoBannerListView.as_view(), name='promo-banners'),
    path('', include(router.urls)),
]

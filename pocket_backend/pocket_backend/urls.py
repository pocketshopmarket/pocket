"""
URL configuration for pocket_backend project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/6.0/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.http import JsonResponse
from django.urls import path, include
from rest_framework_simplejwt.views import TokenRefreshView


def _root(_request):
    return JsonResponse(
        {
            'service': 'Pocket Shop backend',
            'api': '/api/',
            'admin': '/admin/',
        }
    )


def _api_root(_request):
    return JsonResponse(
        {
            'detail': 'API root',
            'prefixes': [
                '/api/auth/',
                '/api/products/',
                '/api/orders/',
                '/api/delivery/',
                '/api/reviews/',
            ],
        }
    )


urlpatterns = [
    path('', include('portal.urls')),
    path('api/', _api_root),
    path('admin/', admin.site.urls),
    # More specific than `api/auth/` include so JWT refresh resolves correctly.
    path('api/auth/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('api/auth/', include('accounts.urls')),
    path('api/products/', include('products.urls')),
    path('api/orders/', include('orders.urls')),
    path('api/delivery/', include('delivery.urls')),
    path('api/reviews/', include('reviews.urls')),
    path('api/payments/', include('payments.urls')),
    path('api/notifications/', include('notifications.urls')),
]

urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)

import logging
import json

import django_filters
from django.db.models import Avg, Count, F, Prefetch, Q
from django.utils.decorators import method_decorator
from django.views.decorators.cache import cache_page
from django_filters.rest_framework import DjangoFilterBackend
from rest_framework import filters, permissions, status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response

from accounts.permissions import IsApprovedSeller
from .models import MAX_PRODUCT_IMAGES, Product, ProductImage
from .pagination import ProductPagination
from .serializers import ProductSerializer

logger = logging.getLogger(__name__)


class ProductFilterSet(django_filters.FilterSet):
    min_price = django_filters.NumberFilter(field_name='price', lookup_expr='gte')
    max_price = django_filters.NumberFilter(field_name='price', lookup_expr='lte')
    in_stock = django_filters.BooleanFilter(method='filter_in_stock')

    class Meta:
        model = Product
        fields = ['category', 'is_available']

    def filter_in_stock(self, queryset, name, value):
        if value is True:
            return queryset.filter(stock_quantity__gt=0, is_available=True)
        if value is False:
            return queryset.filter(Q(stock_quantity__lte=0) | Q(is_available=False))
        return queryset


class ProductViewSet(viewsets.ModelViewSet):
    serializer_class = ProductSerializer
    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [JSONParser, MultiPartParser, FormParser]
    pagination_class = ProductPagination
    filterset_class = ProductFilterSet
    filter_backends = [
        DjangoFilterBackend,
        filters.SearchFilter,
        filters.OrderingFilter,
    ]
    search_fields = ['name', 'description', 'seller__full_name', 'seller__seller_profile__shop_name']
    ordering_fields = ['price', 'created_at', 'name', 'views_count', 'purchases_count']
    ordering = ['-created_at']

    def _require_approved_seller(self):
        if self.request.user.role != 'seller':
            raise PermissionDenied('Only sellers can manage products.')
        seller_profile = getattr(self.request.user, 'seller_profile', None)
        if not seller_profile or not seller_profile.is_approved:
            raise PermissionDenied('Seller approval is required to manage products.')

    def get_queryset(self):
        user = self.request.user
        qs = Product.objects.select_related('seller').prefetch_related(
            'gallery_images',
            Prefetch('variants'),
        ).annotate(
            review_avg=Avg('reviews__rating'),
            review_count=Count('reviews', distinct=True),
        )
        if user.role == 'seller':
            qs = qs.filter(seller=user)
        elif user.role in ['buyer', 'delivery', 'admin']:
            qs = qs.filter(is_available=True)
        else:
            return Product.objects.none()
        return qs

    def get_permissions(self):
        if self.action in ['create', 'update', 'partial_update', 'destroy']:
            return [permissions.IsAuthenticated(), IsApprovedSeller()]
        return super().get_permissions()

    def get_serializer_context(self):
        ctx = super().get_serializer_context()
        ctx['request'] = self.request
        return ctx

    def _validate_image_files(self, files):
        if len(files) > MAX_PRODUCT_IMAGES:
            raise ValidationError(
                {'images': [f'You can upload at most {MAX_PRODUCT_IMAGES} images.']}
            )

    def _replace_gallery(self, product, files):
        self._validate_image_files(files)
        product.gallery_images.all().delete()
        for i, uploaded in enumerate(files):
            ProductImage.objects.create(
                product=product,
                image=uploaded,
                sort_order=i,
            )

    def _normalized_payload(self, request):
        payload = request.data.copy()
        raw_variants = payload.get('variant_payload')
        if isinstance(raw_variants, str) and raw_variants.strip():
            try:
                payload['variant_payload'] = json.loads(raw_variants)
            except json.JSONDecodeError:
                pass
        return payload

    def create(self, request, *args, **kwargs):
        self._require_approved_seller()
        serializer = self.get_serializer(data=self._normalized_payload(request))
        if not serializer.is_valid():
            logger.warning("Product create validation errors: %s", serializer.errors)
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        files = request.FILES.getlist('images')
        try:
            self._validate_image_files(files)
        except ValidationError as e:
            return Response(e.detail, status=status.HTTP_400_BAD_REQUEST)

        product = serializer.save(seller=request.user)
        for i, uploaded in enumerate(files):
            ProductImage.objects.create(
                product=product,
                image=uploaded,
                sort_order=i,
            )

        out = self.get_serializer(
            Product.objects.prefetch_related('gallery_images').get(pk=product.pk)
        )
        return Response(out.data, status=status.HTTP_201_CREATED)

    def update(self, request, *args, **kwargs):
        self._require_approved_seller()
        partial = kwargs.pop('partial', False)
        instance = self.get_object()
        if instance.seller_id != request.user.id:
            raise PermissionDenied('You can only update your own products.')

        serializer = self.get_serializer(
            instance,
            data=self._normalized_payload(request),
            partial=partial,
        )
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        product = serializer.save()
        files = request.FILES.getlist('images')
        if files:
            try:
                self._replace_gallery(product, files)
            except ValidationError as e:
                return Response(e.detail, status=status.HTTP_400_BAD_REQUEST)

        product = Product.objects.prefetch_related('gallery_images').get(pk=product.pk)
        return Response(self.get_serializer(product).data)

    def perform_destroy(self, instance):
        self._require_approved_seller()
        if instance.seller_id != self.request.user.id:
            raise PermissionDenied('You can only delete your own products.')
        instance.delete()

    @method_decorator(cache_page(30))
    def list(self, request, *args, **kwargs):
        return super().list(request, *args, **kwargs)

    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        Product.objects.filter(pk=instance.pk).update(views_count=F('views_count') + 1)
        instance.refresh_from_db()
        serializer = self.get_serializer(instance)
        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    @method_decorator(cache_page(30))
    def trending(self, request):
        queryset = self.filter_queryset(self.get_queryset()).order_by(
            '-purchases_count',
            '-views_count',
            '-created_at',
        )
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        serializer = self.get_serializer(queryset[:20], many=True)
        return Response(serializer.data)

    @action(detail=True, methods=['get'])
    @method_decorator(cache_page(30))
    def related(self, request, pk=None):
        product = self.get_object()
        queryset = self.get_queryset().exclude(pk=product.pk).filter(
            Q(category=product.category) | Q(seller_id=product.seller_id),
        ).order_by('-purchases_count', '-views_count', '-created_at')
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        serializer = self.get_serializer(queryset[:20], many=True)
        return Response(serializer.data)

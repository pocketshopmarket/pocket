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
from rest_framework.views import APIView
from django.core.cache import cache
from django.utils import timezone
from datetime import timedelta

from accounts.permissions import IsApprovedSeller
from .models import MAX_PRODUCT_IMAGES, Product, ProductImage, Category, UserInterest, SearchHistory, ProductInteraction, PromoBanner
from .pagination import ProductPagination
from .serializers import ProductSerializer, CategorySerializer, PromoBannerSerializer

logger = logging.getLogger(__name__)


class CategoryViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Category.objects.all()
    serializer_class = CategorySerializer
    permission_classes = [permissions.AllowAny]
    pagination_class = None

class RecommendedProductsView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        user = request.user
        category_filter = request.query_params.get('category')
        
        # Make sure user has a buyer profile for advanced recommendations
        if not hasattr(user, 'buyer_profile'):
            # Cold start fallback for non-buyers
            qs = Product.objects.filter(is_available=True)
            if category_filter and category_filter.lower() != 'all':
                try:
                    qs = qs.filter(category_id=int(category_filter))
                except (ValueError, TypeError):
                    qs = qs.filter(category__slug__iexact=category_filter)
            products = qs.order_by('-created_at', '-views_count')[:20]
            serializer = ProductSerializer(products, many=True, context={'request': request})
            return Response(serializer.data)

        buyer_profile = user.buyer_profile
        
        # Pagination params
        limit = int(request.query_params.get('limit', 20))
        offset = int(request.query_params.get('offset', 0))
        
        # Check cache (include category in key)
        cache_key = f"recommendations_{buyer_profile.id}_{limit}_{offset}_{category_filter or 'all'}"
        cached_result = cache.get(cache_key)
        
        if cached_result:
            return Response(cached_result)

        # 1. Gather signals
        interests = dict(UserInterest.objects.filter(user=buyer_profile).values_list('category_id', 'weight'))
        
        searches = SearchHistory.objects.filter(user=buyer_profile).order_by('-timestamp')[:10]
        keywords = [s.query for s in searches if s.query]
        
        # Recent interactions
        thirty_days_ago = timezone.now() - timedelta(days=30)
        interactions = ProductInteraction.objects.filter(user=buyer_profile, timestamp__gte=thirty_days_ago).order_by('-timestamp')[:50]
        
        interacted_categories = {}
        for i in interactions:
            if i.product.category_id:
                # Weight interactions: cart > click > view
                weight = 1
                if i.interaction_type == ProductInteraction.CLICK:
                    weight = 2
                elif i.interaction_type == ProductInteraction.ADD_TO_CART:
                    weight = 4
                interacted_categories[i.product.category_id] = interacted_categories.get(i.product.category_id, 0) + weight

        # Base Query
        products = Product.objects.filter(is_available=True, stock_quantity__gt=0)
        if category_filter and category_filter.lower() != 'all':
            try:
                products = products.filter(category_id=int(category_filter))
            except (ValueError, TypeError):
                products = products.filter(category__slug__iexact=category_filter)
        scored_products = []

        for product in products:
            score = 0.0

            # Interest match
            if product.category_id in interests:
                score += (5.0 * interests[product.category_id])

            # Interaction history category match
            if product.category_id in interacted_categories:
                score += interacted_categories[product.category_id]

            # Search match
            for keyword in keywords:
                if keyword.lower() in product.name.lower() or keyword.lower() in product.description.lower():
                    score += 3.0
            
            # Popularity boost
            score += (product.views_count * 0.1)
            score += (product.purchases_count * 0.5)

            # Freshness boost (last 7 days)
            if product.created_at >= timezone.now() - timedelta(days=7):
                score += 2.0

            scored_products.append((product, score))

        # Sort by score descending
        scored_products.sort(key=lambda x: x[1], reverse=True)
        
        # Paginate
        paginated_results = [p[0] for p in scored_products[offset:offset+limit]]

        serializer = ProductSerializer(paginated_results, many=True, context={'request': request})
        data = serializer.data
        
        # Cache for 1 hour
        cache.set(cache_key, data, 60 * 60)
        
        return Response(data)

class TrackInteractionView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        user = request.user
        if not hasattr(user, 'buyer_profile'):
            return Response({'error': 'Must be a buyer'}, status=400)
            
        product_id = request.data.get('product_id')
        interaction_type = request.data.get('interaction_type', ProductInteraction.VIEW)
        
        if not product_id:
            return Response({'error': 'product_id required'}, status=400)
            
        try:
            product = Product.objects.get(id=product_id)
            ProductInteraction.objects.create(
                user=user.buyer_profile,
                product=product,
                interaction_type=interaction_type
            )
            
            # Update product views count if it's a view
            if interaction_type == ProductInteraction.VIEW:
                product.views_count += 1
                product.save(update_fields=['views_count'])
                
            # Invalidate cache since interaction changes scoring
            cache_key_prefix = f"recommendations_{user.buyer_profile.id}"
            # Django cache doesn't easily delete by prefix, but we'll let it expire naturally or explicitly clear exact keys if needed
            
            return Response({'success': True})
        except Product.DoesNotExist:
            return Response({'error': 'Product not found'}, status=404)


class ProductFilterSet(django_filters.FilterSet):
    min_price = django_filters.NumberFilter(field_name='price', lookup_expr='gte')
    max_price = django_filters.NumberFilter(field_name='price', lookup_expr='lte')
    in_stock = django_filters.BooleanFilter(method='filter_in_stock')
    # Accept either category ID (integer) or slug (string)
    category = django_filters.CharFilter(method='filter_category')

    class Meta:
        model = Product
        fields = ['is_available']

    def filter_category(self, queryset, name, value):
        if not value or value.lower() == 'all':
            return queryset
        # Try as integer ID first
        try:
            cat_id = int(value)
            return queryset.filter(category_id=cat_id)
        except (ValueError, TypeError):
            pass
        # Fall back to slug match
        return queryset.filter(category__slug__iexact=value)

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
        if not seller_profile or not seller_profile.can_sell:
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
        # QueryDict (multipart) stores values as lists internally, so converting
        # to a plain dict before we set variant_payload prevents double-wrapping
        # ([parsed_list] instead of parsed_list) that causes DictField validation
        # to see a list where it expects a dict.
        if hasattr(request.data, 'dict'):
            payload = request.data.dict()
        else:
            payload = dict(request.data)

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


class PromoBannerListView(APIView):
    """Active promo banners for the buyer home screen. Public endpoint."""
    permission_classes = [permissions.AllowAny]

    @method_decorator(cache_page(60))
    def get(self, request):
        now = timezone.now()
        qs = PromoBanner.objects.filter(
            is_active=True,
        ).filter(
            Q(starts_at__isnull=True) | Q(starts_at__lte=now),
        ).filter(
            Q(ends_at__isnull=True) | Q(ends_at__gte=now),
        )
        serializer = PromoBannerSerializer(
            qs, many=True, context={'request': request},
        )
        return Response(serializer.data)

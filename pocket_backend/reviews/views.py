from django.db.models import Avg, Count
from django.shortcuts import get_object_or_404
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from products.models import Product

from .models import ProductReview
from .serializers import ProductReviewSerializer


class ProductReviewListCreateView(APIView):
    def get_permissions(self):
        # Reading reviews is part of browsing a product and must stay open
        # to guests (Apple Guideline 5.1.1); only submitting one requires
        # an account.
        if self.request.method == 'POST':
            return [permissions.IsAuthenticated()]
        return [permissions.AllowAny()]

    def get(self, request, product_id):
        product = get_object_or_404(Product, id=product_id)
        queryset = ProductReview.objects.filter(product=product).select_related('author')
        summary = queryset.aggregate(avg=Avg('rating'), count=Count('id'))
        return Response(
            {
                'summary': {
                    'average_rating': float(summary['avg'] or 0),
                    'review_count': summary['count'] or 0,
                },
                'results': ProductReviewSerializer(queryset, many=True).data,
            }
        )

    def post(self, request, product_id):
        product = get_object_or_404(Product, id=product_id, is_available=True)
        serializer = ProductReviewSerializer(
            data=request.data,
            context={'request': request, 'product': product},
        )
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        review = serializer.save()
        return Response(ProductReviewSerializer(review).data, status=status.HTTP_201_CREATED)

from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.authentication import SellerApiKeyAuthentication
from accounts.permissions import IsApprovedSeller
from products.models import Product

from .serializers import PartnerProductSerializer
from .throttles import PartnerAPIThrottle


class PartnerProductUpsertView(APIView):
    """
    POST /api/partner/v1/products/

    Single-item idempotent upsert, keyed by external_id (scoped per seller,
    never globally): the first call for a given external_id creates the
    product (201), every subsequent call updates it in place (200) instead
    of creating a duplicate. seller is always resolved from the API key,
    never trusted from the request body — same rule ProductViewSet.create()
    already follows for JWT-authenticated sellers.
    """
    authentication_classes = [SellerApiKeyAuthentication]
    permission_classes = [IsApprovedSeller]
    throttle_classes = [PartnerAPIThrottle]

    def post(self, request):
        external_id = str(request.data.get('external_id', '')).strip()
        if not external_id:
            return Response(
                {'external_id': ['This field is required.']},
                status=status.HTTP_400_BAD_REQUEST,
            )

        existing = Product.objects.filter(
            seller=request.user, external_id=external_id,
        ).first()
        serializer = PartnerProductSerializer(instance=existing, data=request.data)
        serializer.is_valid(raise_exception=True)
        product = serializer.save(seller=request.user, external_id=external_id)

        payload = PartnerProductSerializer(product).data
        payload['created'] = existing is None
        return Response(
            payload,
            status=status.HTTP_201_CREATED if existing is None else status.HTTP_200_OK,
        )

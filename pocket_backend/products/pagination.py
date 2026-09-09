from rest_framework.pagination import PageNumberPagination


class ProductPagination(PageNumberPagination):
    page_size = 12
    page_size_query_param = 'page_size'
    # Was 50 — too low for a seller's own "my products" screen to ever
    # fetch a full catalog in one request (272+ items is real, not
    # hypothetical). Buyer-facing screens are unaffected since they still
    # request their own small page_size by default; this only raises the
    # ceiling a client is allowed to ask for.
    max_page_size = 500

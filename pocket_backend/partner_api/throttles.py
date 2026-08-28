from rest_framework.throttling import SimpleRateThrottle


class PartnerAPIThrottle(SimpleRateThrottle):
    """
    Per-API-key ceiling for partner product sync — not per-seller, since a
    seller can mint multiple keys (e.g. staging vs. production, or two
    different integrations) and keying by seller would let one misbehaving
    key exhaust the shared budget and starve the seller's other key.
    """
    scope = 'partner_api'

    def get_cache_key(self, request, view):
        api_key = getattr(request, 'seller_api_key', None)
        ident = str(api_key.id) if api_key else self.get_ident(request)
        return self.cache_format % {'scope': self.scope, 'ident': ident}

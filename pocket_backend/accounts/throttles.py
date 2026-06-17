from rest_framework.throttling import SimpleRateThrottle


class LoginRateThrottle(SimpleRateThrottle):
    """5 password-login attempts per minute, keyed by phone number (falls back to IP)."""
    scope = 'login'

    def get_cache_key(self, request, view):
        phone = (request.data.get('phone_number') or '').strip()
        ident = phone if phone else self.get_ident(request)
        return self.cache_format % {'scope': self.scope, 'ident': ident}


class QRVerifyThrottle(SimpleRateThrottle):
    """10 QR scan attempts per minute per rider (prevents brute-force QR guessing)."""
    scope = 'qr_verify'

    def get_cache_key(self, request, view):
        user = request.user
        ident = str(user.id) if user and user.is_authenticated else self.get_ident(request)
        return self.cache_format % {'scope': self.scope, 'ident': ident}

"""
Resolve pickup / delivery map coordinates with geocoding and DB caching.
"""
from __future__ import annotations

import hashlib

from accounts.models import SellerProfile
from django.conf import settings
from django.core.cache import cache
from orders.models import Order

from .utils import LocationService


def geocode_cached(address: str) -> dict | None:
    """Nominatim with process-wide cache (Phase 5)."""
    text = (address or '').strip()
    if not text:
        return None

    key = 'geo:' + hashlib.sha256(text.lower().encode()).hexdigest()[:48]
    hit = cache.get(key)
    if hit is not None:
        if isinstance(hit, dict) and hit.get('_miss'):
            return None
        return hit if isinstance(hit, dict) else None

    geo = LocationService.geocode_address(text)
    ttl = getattr(settings, 'GEOCODING_CACHE_TTL', 86400)
    if geo:
        cache.set(key, geo, timeout=ttl)
    else:
        cache.set(key, {'_miss': True}, timeout=300)
    return geo


def resolve_pickup_coordinates(seller, allow_fallback: bool = True) -> dict | None:
    """
    Seller shop coordinates for pickup. Uses cached shop_lat/shop_lng when set;
    otherwise geocodes shop_location and caches on SellerProfile.
    """
    fallback = LocationService.get_lusaka_center() if allow_fallback else None

    profile = SellerProfile.objects.filter(user=seller).first()
    if not profile:
        return fallback

    if profile.shop_lat is not None and profile.shop_lng is not None:
        return {'lat': float(profile.shop_lat), 'lng': float(profile.shop_lng)}

    text = (profile.shop_location or '').strip()
    if not text:
        return fallback

    geo = geocode_cached(text)
    if geo:
        profile.shop_lat = geo['lat']
        profile.shop_lng = geo['lng']
        profile.save(update_fields=['shop_lat', 'shop_lng'])
        return {'lat': geo['lat'], 'lng': geo['lng']}

    return fallback


def resolve_delivery_coordinates(order: Order, allow_fallback: bool = True) -> dict | None:
    """
    Buyer drop-off coordinates. Uses cached delivery_lat/delivery_lng when set;
    otherwise geocodes delivery_address and caches on Order.
    """
    fallback = LocationService.get_lusaka_center() if allow_fallback else None

    if order.delivery_lat is not None and order.delivery_lng is not None:
        return {'lat': float(order.delivery_lat), 'lng': float(order.delivery_lng)}

    text = (order.delivery_address or '').strip()
    if not text:
        return fallback

    geo = geocode_cached(text)
    if geo:
        order.delivery_lat = geo['lat']
        order.delivery_lng = geo['lng']
        order.save(update_fields=['delivery_lat', 'delivery_lng'])
        return {'lat': geo['lat'], 'lng': geo['lng']}

    return fallback


def build_pickup_coords_for_orders(orders, allow_fallback: bool = True) -> dict:
    """Map order id -> pickup dict for serializers (avoids repeated work per seller)."""
    by_seller: dict[int, dict] = {}
    result: dict[int, dict] = {}

    for order in orders:
        sid = order.seller_id
        if sid not in by_seller:
            by_seller[sid] = resolve_pickup_coordinates(
                order.seller, allow_fallback=allow_fallback
            )
        result[order.id] = by_seller[sid]

    return result

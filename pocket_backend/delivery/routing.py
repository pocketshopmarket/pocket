"""
Routing helpers with provider chain, confidence scoring, and fallback estimates.
"""
from __future__ import annotations

import hashlib
import logging
import math

import requests
from django.conf import settings
from django.core.cache import cache
from django.utils import timezone

logger = logging.getLogger(__name__)


def _route_cache_key(start: dict, end: dict, provider: str) -> str:
    s = (
        f"{provider}|{start['lat']:.5f},{start['lng']:.5f}|"
        f"{end['lat']:.5f},{end['lng']:.5f}"
    )
    h = hashlib.sha256(s.encode()).hexdigest()[:48]
    return f"route:{h}"


def _haversine_km(start: dict, end: dict) -> float:
    lat1 = math.radians(float(start["lat"]))
    lat2 = math.radians(float(end["lat"]))
    dlat = lat2 - lat1
    dlng = math.radians(float(end["lng"]) - float(start["lng"]))
    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin(dlng / 2) ** 2
    )
    return 6371 * (2 * math.atan2(math.sqrt(a), math.sqrt(1 - a)))


def _osrm_confidence(distance_m: float, duration_s: float, crow_km: float) -> float:
    if distance_m <= 0 or duration_s <= 0:
        return 0.0
    road_km = distance_m / 1000.0
    ratio = road_km / max(crow_km, 0.05)
    score = 0.86
    if ratio < 1.03:
        score -= 0.35
    elif ratio < 1.10:
        score -= 0.10
    elif ratio > 4.2:
        score -= 0.45
    elif ratio > 3.2:
        score -= 0.25
    elif ratio > 2.6:
        score -= 0.12

    speed_kmh = road_km / max(duration_s / 3600.0, 0.01)
    if speed_kmh < 8 or speed_kmh > 95:
        score -= 0.25
    elif speed_kmh < 12 or speed_kmh > 80:
        score -= 0.10

    return max(0.0, min(1.0, round(score, 2)))


def _fetch_osrm_route(start: dict, end: dict) -> dict | None:
    try:
        slng, slat = float(start["lng"]), float(start["lat"])
        elng, elat = float(end["lng"]), float(end["lat"])
    except (KeyError, TypeError, ValueError):
        return None

    cache_key = _route_cache_key(
        {"lat": slat, "lng": slng}, {"lat": elat, "lng": elng}, "osrm"
    )
    cached = cache.get(cache_key)
    if cached is not None:
        return cached

    base = getattr(settings, "OSRM_BASE_URL", "https://router.project-osrm.org")
    url = f"{base}/route/v1/driving/{slng},{slat};{elng},{elat}"
    params = {"overview": "full", "geometries": "geojson"}
    headers = {
        "User-Agent": getattr(settings, "NOMINATIM_USER_AGENT", "PocketShop/1.0")
    }

    try:
        r = requests.get(url, params=params, headers=headers, timeout=12)
        r.raise_for_status()
        data = r.json()
    except (requests.RequestException, ValueError) as exc:
        logger.warning("OSRM route failed: %s", exc)
        return None

    routes = data.get("routes") or []
    if not routes:
        return None

    route0 = routes[0] or {}
    geom = route0.get("geometry") or {}
    coords = geom.get("coordinates")
    if not coords or not isinstance(coords, list):
        return None

    distance_m = float(route0.get("distance") or 0)
    duration_s = float(route0.get("duration") or 0)
    crow_km = _haversine_km(start, end)
    out = {
        "coordinates": coords,
        "distance_m": distance_m,
        "duration_s": duration_s,
        "route_source": "osrm",
        "route_confidence": _osrm_confidence(distance_m, duration_s, crow_km),
    }
    ttl = getattr(settings, "ROUTING_CACHE_TTL", 3600)
    cache.set(cache_key, out, timeout=ttl)
    return out


def _fallback_straight_route(start: dict, end: dict) -> dict:
    distance_km = _haversine_km(start, end)
    avg_speed = max(
        8.0,
        float(getattr(settings, "ROUTING_FALLBACK_SPEED_KMH", 28.0)),
    )
    duration_h = distance_km / avg_speed if distance_km > 0 else 0
    return {
        "coordinates": [
            [float(start["lng"]), float(start["lat"])],
            [float(end["lng"]), float(end["lat"])],
        ],
        "distance_m": distance_km * 1000.0,
        "duration_s": duration_h * 3600.0,
        "route_source": "haversine_fallback",
        "route_confidence": 0.32,
    }


def _calibrated_duration_minutes(distance_m: float, duration_s: float) -> int | None:
    if distance_m <= 0 or duration_s <= 0:
        return None
    distance_km = distance_m / 1000.0
    raw_minutes = duration_s / 60.0
    avg_speed_kmh = distance_km / max(duration_s / 3600.0, 0.01)

    traffic_multiplier = max(
        1.0, float(getattr(settings, "DELIVERY_TRAFFIC_MULTIPLIER", 1.2))
    )
    max_avg_speed = float(getattr(settings, "DELIVERY_MAX_AVG_SPEED_KMH", 38.0))
    preferred_avg_speed = float(getattr(settings, "DELIVERY_AVG_SPEED_KMH", 22.0))
    min_eta = int(getattr(settings, "DELIVERY_MIN_ETA_MINUTES", 4))

    calibrated = raw_minutes * traffic_multiplier
    # If provider duration implies unrealistic average speed for local urban delivery,
    # clamp ETA using configured average speed.
    if avg_speed_kmh > max_avg_speed:
        fallback_minutes = (distance_km / max(preferred_avg_speed, 8.0)) * 60.0
        calibrated = max(calibrated, fallback_minutes)

    return max(min_eta, int(math.ceil(calibrated)))


def fetch_driving_route(start: dict, end: dict) -> dict:
    """
    Return route payload with confidence and source; always falls back.
    """
    providers = getattr(settings, "ROUTING_PROVIDER_ORDER", ["osrm"])
    min_conf = float(getattr(settings, "ROUTING_CONFIDENCE_THRESHOLD", 0.55))
    for provider in providers:
        if provider != "osrm":
            continue
        route = _fetch_osrm_route(start, end)
        if not route:
            continue
        if float(route.get("route_confidence") or 0.0) >= min_conf:
            return route
        logger.info(
            "Low-confidence route (%.2f) from provider=%s",
            float(route.get("route_confidence") or 0.0),
            provider,
        )
    return _fallback_straight_route(start, end)


def apply_route_to_assignment(assignment, start: dict, end: dict) -> None:
    """Mutate assignment with route + confidence fields; caller saves."""
    route = fetch_driving_route(start, end)
    if not route.get("coordinates"):
        return

    assignment.route_coordinates = route["coordinates"]
    assignment.route_distance_m = route["distance_m"]
    assignment.route_duration_s = route["duration_s"]
    assignment.route_source = route.get("route_source") or "unknown"
    assignment.route_confidence = float(route.get("route_confidence") or 0.0)
    assignment.last_eta_recomputed_at = timezone.now()

    if route["distance_m"] > 0:
        assignment.estimated_distance = round(route["distance_m"] / 1000.0, 2)
    calibrated_minutes = _calibrated_duration_minutes(
        float(route.get("distance_m") or 0.0),
        float(route.get("duration_s") or 0.0),
    )
    if calibrated_minutes is not None:
        assignment.estimated_duration = calibrated_minutes

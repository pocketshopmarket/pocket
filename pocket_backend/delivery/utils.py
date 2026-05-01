import math

import requests
from django.conf import settings
from django.utils import timezone

class LocationService:
    WEEKDAY_AGG_BUCKET = 7
    WEEKEND_AGG_BUCKET = 8

    ZAMBIA_CITY_CENTERS = {
        'lusaka': {'lat': -15.3875, 'lng': 28.3228, 'name': 'Lusaka'},
        'kitwe': {'lat': -12.8024, 'lng': 28.2132, 'name': 'Kitwe'},
        'ndola': {'lat': -12.9587, 'lng': 28.6366, 'name': 'Ndola'},
        'kabwe': {'lat': -14.4469, 'lng': 28.4464, 'name': 'Kabwe'},
        'livingstone': {'lat': -17.8419, 'lng': 25.8543, 'name': 'Livingstone'},
    }

    @staticmethod
    def calculate_distance(lat1, lon1, lat2, lon2):
        """Calculate distance between two points using Haversine formula"""
        R = 6371  # Earth's radius in kilometers
        
        lat1_rad = math.radians(float(lat1))
        lat2_rad = math.radians(float(lat2))
        delta_lat = math.radians(float(lat2) - float(lat1))
        delta_lon = math.radians(float(lon2) - float(lon1))
        
        a = (math.sin(delta_lat/2)**2 + 
               math.cos(lat1_rad) * math.cos(lat2_rad) * 
               math.sin(delta_lon/2)**2)
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
        
        return R * c
    
    @staticmethod
    def _profile_avg_speed_kmh(phase: str, at_time=None):
        from .models import DeliverySpeedProfile

        ts = timezone.localtime(at_time or timezone.now())
        min_samples = int(getattr(settings, 'DELIVERY_SPEED_PROFILE_MIN_SAMPLES', 6))
        exact_profile = (
            DeliverySpeedProfile.objects.filter(
                phase=phase,
                weekday=ts.weekday(),
                hour_of_day=ts.hour,
                samples__gte=min_samples,
            )
            .order_by('-samples')
            .first()
        )
        if exact_profile:
            return float(exact_profile.avg_speed_kmh)

        daytype_bucket = (
            LocationService.WEEKEND_AGG_BUCKET
            if ts.weekday() >= 5
            else LocationService.WEEKDAY_AGG_BUCKET
        )
        daytype_min_samples = int(
            getattr(settings, 'DELIVERY_SPEED_PROFILE_DAYTYPE_MIN_SAMPLES', 10)
        )
        daytype_profile = (
            DeliverySpeedProfile.objects.filter(
                phase=phase,
                weekday=daytype_bucket,
                hour_of_day=ts.hour,
                samples__gte=daytype_min_samples,
            )
            .order_by('-samples')
            .first()
        )
        if daytype_profile:
            return float(daytype_profile.avg_speed_kmh)
        return None

    @staticmethod
    def estimate_eta(
        distance_km,
        avg_speed_kmh=None,
        *,
        phase='in_transit',
        at_time=None,
    ):
        """
        Estimate delivery time in minutes using configured average speed
        and a traffic multiplier.
        """
        distance = max(0.0, float(distance_km or 0.0))
        if avg_speed_kmh is None:
            profiled = LocationService._profile_avg_speed_kmh(
                phase=phase, at_time=at_time
            )
            avg_speed_kmh = (
                profiled
                if profiled is not None
                else float(getattr(settings, 'DELIVERY_AVG_SPEED_KMH', 22.0))
            )
        speed = min(max(float(avg_speed_kmh), 8.0), 80.0)
        traffic_multiplier = max(
            1.0, float(getattr(settings, 'DELIVERY_TRAFFIC_MULTIPLIER', 1.2))
        )
        min_eta = int(getattr(settings, 'DELIVERY_MIN_ETA_MINUTES', 4))

        minutes = (distance / speed) * 60.0 * traffic_multiplier
        if distance <= 0:
            return 1
        return max(min_eta, int(math.ceil(minutes)))
    
    @staticmethod
    def calculate_delivery_fee(distance_km: float) -> float:
        """
        Calculate delivery fee using the platform's live pricing config.

        Short trips (≤ threshold km)  → flat rate   (e.g. ZMW 30)
        Long  trips (>  threshold km) → distance × per_km_rate  (e.g. 12 km × ZMW 5)
        """
        from .models import DeliveryPricingConfig
        config = DeliveryPricingConfig.get_config()
        if distance_km <= float(config.short_distance_threshold_km):
            return float(config.short_distance_flat_rate)
        return round(distance_km * float(config.per_km_rate), 2)

    # Keep old method as alias so any existing call-sites don't break immediately.
    @staticmethod
    def calculate_delivery_cost(distance_km, base_rate, per_km_rate):
        """Legacy helper — prefer calculate_delivery_fee()."""
        return float(base_rate) + (distance_km * float(per_km_rate))
    
    @staticmethod
    def geocode_address(address):
        """Convert address to coordinates using Nominatim (OSM)."""
        url = "https://nominatim.openstreetmap.org/search"
        headers = {
            'User-Agent': getattr(
                settings,
                'NOMINATIM_USER_AGENT',
                'PocketShop/1.0 (geocoding)',
            ),
            'Accept-Language': 'en',
        }

        text = (address or '').strip()
        if not text:
            return None

        normalized = text
        words = normalized.split()
        if words:
            expanded = []
            for w in words:
                lw = w.lower().strip('.,')
                if lw == 'cbd':
                    expanded.append('central business district')
                else:
                    expanded.append(w)
            normalized = ' '.join(expanded)

        attempts = [
            {'q': text, 'countrycodes': 'zm'},
            {'q': normalized, 'countrycodes': 'zm'},
            {'q': f'{text}, Zambia', 'countrycodes': 'zm'},
            {'q': f'{normalized}, Zambia', 'countrycodes': 'zm'},
            {'q': text},
            {'q': normalized},
            {'q': f'{text}, Zambia'},
            {'q': f'{normalized}, Zambia'},
        ]
        for attempt in attempts:
            params = {
                'q': attempt['q'],
                'format': 'json',
                'limit': 1,
            }
            if 'countrycodes' in attempt:
                params['countrycodes'] = attempt['countrycodes']
            try:
                response = requests.get(
                    url, params=params, headers=headers, timeout=10
                )
                if response.status_code == 200:
                    data = response.json()
                    if data:
                        result = data[0]
                        return {
                            'lat': float(result['lat']),
                            'lng': float(result['lon']),
                            'display_name': result['display_name']
                        }
            except Exception as e:
                print(f"Geocoding error: {e}")

        # City-level fallback (better than failing or forcing Lusaka for every case).
        lower_text = text.lower()
        for key, center in LocationService.ZAMBIA_CITY_CENTERS.items():
            if key in lower_text:
                return {
                    'lat': center['lat'],
                    'lng': center['lng'],
                    'display_name': f"{center['name']}, Zambia (city center estimate)",
                }

        return None

    @staticmethod
    def reverse_geocode(lat, lng):
        """Convert coordinates to readable place name using Nominatim."""
        url = "https://nominatim.openstreetmap.org/reverse"
        params = {
            'lat': lat,
            'lon': lng,
            'format': 'jsonv2',
            'zoom': 18,
            'addressdetails': 1,
        }
        headers = {
            'User-Agent': getattr(
                settings,
                'NOMINATIM_USER_AGENT',
                'PocketShop/1.0 (reverse-geocoding)',
            ),
            'Accept-Language': 'en',
        }
        try:
            response = requests.get(
                url, params=params, headers=headers, timeout=10
            )
            if response.status_code == 200:
                data = response.json()
                if data and data.get('display_name'):
                    return {
                        'lat': float(data.get('lat') or lat),
                        'lng': float(data.get('lon') or lng),
                        'display_name': data['display_name'],
                    }
        except Exception as e:
            print(f"Reverse geocoding error: {e}")
        return None

    @staticmethod
    def search_address_suggestions(query, limit=5):
        """Return address suggestions from Nominatim for user typing."""
        text = (query or '').strip()
        if not text:
            return []
        url = "https://nominatim.openstreetmap.org/search"
        params = {
            'q': text,
            'format': 'json',
            'limit': max(1, min(int(limit), 10)),
            'countrycodes': 'zm',
            'addressdetails': 1,
        }
        headers = {
            'User-Agent': getattr(
                settings,
                'NOMINATIM_USER_AGENT',
                'PocketShop/1.0 (autocomplete)',
            ),
            'Accept-Language': 'en',
        }
        out = []
        try:
            response = requests.get(
                url, params=params, headers=headers, timeout=10
            )
            if response.status_code == 200:
                data = response.json()
                for row in data or []:
                    try:
                        out.append(
                            {
                                'display_name': row.get('display_name', ''),
                                'lat': float(row.get('lat')),
                                'lng': float(row.get('lon')),
                            }
                        )
                    except (TypeError, ValueError):
                        continue
        except Exception as e:
            print(f"Address search error: {e}")
        return out
    
    @staticmethod
    def get_lusaka_center():
        """Get Lusaka city center coordinates"""
        return {'lat': -15.3875, 'lng': 28.3228}


def create_delivery_offers_for_order(order, top_n=5, expires_in_minutes=3):
    """
    Create delivery offers for nearest available riders when seller marks ready.
    Returns number of offers created.
    """
    from datetime import timedelta
    from django.utils import timezone
    from accounts.models import DeliveryProfile
    from delivery.models import DeliveryAssignment, DeliveryOffer
    from delivery.coordinates import resolve_pickup_coordinates

    if DeliveryAssignment.objects.filter(order=order).exclude(
        status__in=['delivered', 'cancelled']
    ).exists():
        return 0

    pickup = resolve_pickup_coordinates(order.seller)
    pickup_lat = pickup.get('lat')
    pickup_lng = pickup.get('lng')
    if pickup_lat is None or pickup_lng is None:
        return 0

    # Fresh start whenever order becomes out_for_delivery again.
    DeliveryOffer.objects.filter(order=order, status='pending').update(status='expired')

    candidates = []
    qs = DeliveryProfile.objects.filter(
        is_available=True,
        is_approved=True,
        current_location_lat__isnull=False,
        current_location_lng__isnull=False,
    ).select_related('user')

    for p in qs:
        busy = DeliveryAssignment.objects.filter(
            delivery_person=p.user,
            status__in=['accepted', 'picked_up', 'in_transit'],
        ).exists()
        if busy:
            continue
        distance_km = LocationService.calculate_distance(
            p.current_location_lat,
            p.current_location_lng,
            pickup_lat,
            pickup_lng,
        )
        candidates.append((distance_km, p.user))

    candidates.sort(key=lambda x: x[0])
    if not candidates:
        return 0

    now = timezone.now()
    expires_at = now + timedelta(minutes=expires_in_minutes)
    created = 0
    for distance_km, rider in candidates[:top_n]:
        DeliveryOffer.objects.create(
            order=order,
            rider=rider,
            status='pending',
            expires_at=expires_at,
            rider_distance_km=round(distance_km, 2),
        )
        created += 1
    return created

import 'package:geolocator/geolocator.dart';

enum LocationStatus { success, servicesDisabled, permissionDenied, error }

/// Result of a `LocationHelper.getCurrentPositionOrFallback()` call.
/// Never throws — callers branch on `status` and show their own fallback
/// message, since existing call sites each word that message differently.
class LocationResult {
  const LocationResult._(this.status, this.lat, this.lng);

  factory LocationResult.success(double lat, double lng) =>
      LocationResult._(LocationStatus.success, lat, lng);
  factory LocationResult.servicesDisabled() =>
      const LocationResult._(LocationStatus.servicesDisabled, null, null);
  factory LocationResult.permissionDenied() =>
      const LocationResult._(LocationStatus.permissionDenied, null, null);
  factory LocationResult.error() =>
      const LocationResult._(LocationStatus.error, null, null);

  final LocationStatus status;
  final double? lat;
  final double? lng;

  bool get isSuccess => status == LocationStatus.success;
}

/// Shared check → request → getCurrentPosition flow, extracted from the
/// near-identical blocks previously duplicated in cart_screen.dart,
/// buyer_profile_screen.dart, and delivery_home_screen.dart.
class LocationHelper {
  static Future<LocationResult> getCurrentPositionOrFallback() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationResult.servicesDisabled();
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return LocationResult.permissionDenied();
      }
      final pos = await Geolocator.getCurrentPosition();
      return LocationResult.success(pos.latitude, pos.longitude);
    } catch (_) {
      return LocationResult.error();
    }
  }
}

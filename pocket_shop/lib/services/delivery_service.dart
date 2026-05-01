import 'package:dio/dio.dart';

import '../core/constants/app_constants.dart';
import 'api_service.dart';

class DeliveryService {
  final ApiService _api = ApiService();

  Future<List<Map<String, dynamic>>> fetchAvailableOrders({
    required double lat,
    required double lng,
  }) async {
    final response = await _api.get(
      AppConstants.deliveryAvailableEndpoint,
      queryParameters: {'lat': lat, 'lng': lng},
    );
    final data = response.data;
    if (data is List) {
      return data
          .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
          .toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> acceptOrder({
    required int orderId,
    required double lat,
    required double lng,
  }) async {
    final response = await _api.post(
      AppConstants.deliveryAcceptEndpoint,
      data: {
        'order_id': orderId,
        'lat': double.parse(lat.toStringAsFixed(8)),
        'lng': double.parse(lng.toStringAsFixed(8)),
      },
    );
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    throw Exception('Invalid accept response');
  }

  Future<void> updateLocation({
    required int assignmentId,
    required double lat,
    required double lng,
    double? speed,
    double? accuracy,
  }) async {
    await _api.post(
      AppConstants.deliveryLocationEndpoint,
      data: {
        'assignment_id': assignmentId,
        'lat': double.parse(lat.toStringAsFixed(8)),
        'lng': double.parse(lng.toStringAsFixed(8)),
        if (speed != null) 'speed': speed,
        if (accuracy != null) 'accuracy': accuracy,
      },
    );
  }

  Future<Map<String, dynamic>> updateAssignmentStatus({
    required int assignmentId,
    required String status,
    bool simulateQr = false,
  }) async {
    final path =
        '${AppConstants.deliveryAssignmentStatusPrefix}$assignmentId/status/';
    final response = await _api.put(
      path,
      data: {
        'status': status,
        if (simulateQr) 'simulate_qr': true,
      },
    );
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    throw Exception('Invalid status response');
  }

  /// `null` if no active job.
  Future<Map<String, dynamic>?> fetchActiveAssignment() async {
    final response = await _api.get(AppConstants.deliveryActiveAssignmentEndpoint);
    final data = response.data;
    if (data is! Map) return null;
    final m = Map<String, dynamic>.from(data);
    final a = m['assignment'];
    if (a == null) return null;
    if (a is Map<String, dynamic>) return a;
    if (a is Map) return Map<String, dynamic>.from(a);
    return null;
  }

  Future<List<Map<String, dynamic>>> fetchZones() async {
    final response = await _api.get(AppConstants.deliveryZonesEndpoint);
    final data = response.data;
    if (data is List) {
      return data
          .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
          .toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> fetchQuote({
    required double deliveryLat,
    required double deliveryLng,
    double? pickupLat,
    double? pickupLng,
    int? sellerId,
  }) async {
    final body = <String, dynamic>{
      'delivery_lat': deliveryLat,
      'delivery_lng': deliveryLng,
    };
    if (pickupLat != null && pickupLng != null) {
      body['pickup_lat'] = pickupLat;
      body['pickup_lng'] = pickupLng;
    }
    if (sellerId != null) {
      body['seller_id'] = sellerId;
    }
    final response = await _api.post(AppConstants.deliveryQuoteEndpoint, data: body);
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return {};
  }

  Future<Map<String, dynamic>> fetchStats() async {
    final response = await _api.get(AppConstants.deliveryStatsEndpoint);
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return {};
  }

  /// Returns the platform delivery pricing config:
  /// { short_distance_threshold_km, short_distance_flat_rate, per_km_rate }
  Future<Map<String, dynamic>> fetchPricingConfig() async {
    final response = await _api.get('/delivery/pricing/');
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Future<Map<String, dynamic>> generateHandoffToken({
    required int assignmentId,
    required String step,
  }) async {
    final path =
        '${AppConstants.deliveryHandoffTokenPrefix}$assignmentId/handoff/token/';
    final response = await _api.post(path, data: {'step': step});
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Future<Map<String, dynamic>> verifyHandoffToken({
    required int assignmentId,
    required String step,
    required String token,
  }) async {
    final path =
        '${AppConstants.deliveryHandoffTokenPrefix}$assignmentId/handoff/verify/';
    final response = await _api.post(
      path,
      data: {'step': step, 'token': token},
    );
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Future<Map<String, dynamic>?> reverseGeocode({
    required double lat,
    required double lng,
  }) async {
    final response = await _api.get(
      AppConstants.deliveryReverseGeocodeEndpoint,
      queryParameters: {'lat': lat, 'lng': lng},
    );
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Future<List<Map<String, dynamic>>> searchAddressSuggestions(
    String query, {
    int limit = 5,
  }) async {
    final response = await _api.get(
      AppConstants.deliveryAddressSearchEndpoint,
      queryParameters: {'q': query, 'limit': limit},
    );
    final data = response.data;
    if (data is Map) {
      final results = data['results'];
      if (results is List) {
        return results
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    return [];
  }

  String? extractErrorMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final err = data['error'] ?? data['detail'] ?? data['message'];
      if (err != null) return err.toString();
    }
    return e.message;
  }
}

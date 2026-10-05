import 'package:dio/dio.dart';

import '../models/order.dart';
import '../models/transport_request.dart';
import 'api_service.dart';

class TransportService {
  final ApiService _api = ApiService();
  static const String _endpoint = 'orders/transport-requests/';

  Future<List<TransportRequest>> list() async {
    final response = await _api.get(_endpoint);
    final data = response.data;
    if (data is List) {
      return data
          .map((e) => TransportRequest.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<TransportRequest> create({
    required int productId,
    required int quantity,
    required String deliveryAddress,
    required double deliveryLat,
    required double deliveryLng,
  }) async {
    final response = await _api.post(_endpoint, data: {
      'product_id': productId,
      'quantity': quantity,
      'delivery_address': deliveryAddress,
      'delivery_lat': deliveryLat,
      'delivery_lng': deliveryLng,
    });
    return TransportRequest.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TransportRequest> propose({
    required int id,
    required String method,
    required double fee,
  }) async {
    final response = await _api.post(
      '$_endpoint$id/propose/',
      data: {'method': method, 'fee': fee},
    );
    return TransportRequest.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TransportRequest> decline({
    required int id,
    String reason = '',
  }) async {
    final response = await _api.post(
      '$_endpoint$id/decline/',
      data: {'reason': reason},
    );
    return TransportRequest.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Order> accept(int id) async {
    final response = await _api.post('$_endpoint$id/accept/');
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  String? extractErrorMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final err = data['error'] ?? data['detail'] ?? data['message'];
      if (err != null) return err.toString();
      if (data.isNotEmpty) {
        final first = data.values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
        return first.toString();
      }
    }
    return e.message;
  }
}

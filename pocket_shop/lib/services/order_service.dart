import 'dart:convert';
import 'package:dio/dio.dart';

import '../core/constants/app_constants.dart';
import '../models/cart_item.dart';
import '../models/order.dart';
import '../models/product.dart';
import 'api_service.dart';

class OrderService {
  final ApiService _api = ApiService();

  List<CartItem> _parseCartItems(Map<String, dynamic> data) {
    final items = data['items'];
    if (items is! List) return [];
    return items.map((raw) {
      final m = raw as Map<String, dynamic>;
      return CartItem(
        cartItemId: m['id'] as int,
        product: Product.fromCartLine(m),
        quantity: m['quantity'] as int,
      );
    }).toList();
  }

  Future<List<CartItem>> fetchCart() async {
    final response = await _api.get(AppConstants.ordersCartEndpoint);
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return _parseCartItems(data);
    }
    return [];
  }

  Future<List<CartItem>> addToCart({required int productId, required int quantity}) async {
    final response = await _api.post(
      AppConstants.ordersCartEndpoint,
      data: {'product_id': productId, 'quantity': quantity},
    );
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return _parseCartItems(data);
    }
    return [];
  }

  Future<List<CartItem>> updateCartItemQuantity({
    required int cartItemId,
    required int quantity,
  }) async {
    final response = await _api.put(
      '${AppConstants.ordersCartEndpoint}$cartItemId/',
      data: {'quantity': quantity},
    );
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return _parseCartItems(data);
    }
    return [];
  }

  Future<List<CartItem>> removeCartItem(int cartItemId) async {
    final response = await _api.delete('${AppConstants.ordersCartEndpoint}$cartItemId/');
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return _parseCartItems(data);
    }
    return [];
  }

  Future<Order> createOrder({
    required String deliveryAddress,
    String specialInstructions = '',
    String fulfillmentType = 'delivery',
    double? quotedDeliveryFee,
    double? quotedDistanceKm,
    int? quotedEtaMinutes,
    double? deliveryLat,
    double? deliveryLng,
    String? pickupTimeSlot,
  }) async {
    final metadata = <String, dynamic>{
      'fulfillment_type': fulfillmentType,
      if (quotedDeliveryFee != null) 'quoted_delivery_fee': quotedDeliveryFee,
      if (quotedDistanceKm != null) 'quoted_distance_km': quotedDistanceKm,
      if (quotedEtaMinutes != null) 'quoted_eta_minutes': quotedEtaMinutes,
      if (deliveryLat != null) 'delivery_lat': deliveryLat,
      if (deliveryLng != null) 'delivery_lng': deliveryLng,
      if (pickupTimeSlot != null && pickupTimeSlot.trim().isNotEmpty)
        'pickup_time_slot': pickupTimeSlot.trim(),
    };
    final encodedMeta = '[PS_META]${jsonEncode(metadata)}[/PS_META]';
    final trimmedInstructions = specialInstructions.trim();
    final mergedInstructions = trimmedInstructions.isEmpty
        ? encodedMeta
        : '$encodedMeta $trimmedInstructions';

    final response = await _api.post(
      AppConstants.ordersCreateEndpoint,
      data: {
        'delivery_address': deliveryAddress,
        'special_instructions': mergedInstructions,
      },
    );
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return Order.fromJson(data);
    }
    throw Exception('Invalid order response');
  }

  Future<List<Order>> fetchOrders() async {
    final response = await _api.get(AppConstants.ordersListEndpoint);
    final data = response.data;
    if (data is List) {
      return data
          .map((e) => Order.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<Order> fetchOrder(int id) async {
    final response = await _api.get('${AppConstants.ordersListEndpoint}$id/');
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return Order.fromJson(data);
    }
    throw Exception('Order not found');
  }

  Future<List<Map<String, dynamic>>> fetchOrderRatings(int orderId) async {
    final response = await _api.get('${AppConstants.ordersListEndpoint}$orderId/ratings/');
    final data = response.data;
    if (data is List) {
      return data
          .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
          .toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> submitRating({
    required int orderId,
    required String targetRole,
    required int score,
    String comment = '',
  }) async {
    final response = await _api.post(
      '${AppConstants.ordersListEndpoint}$orderId/ratings/',
      data: {
        'target_role': targetRole,
        'score': score,
        'comment': comment,
      },
    );
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Future<Order> updateOrderStatus({
    required int orderId,
    required String status,
  }) async {
    final response = await _api.put(
      '${AppConstants.ordersListEndpoint}$orderId/status/',
      data: {'status': status},
    );
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return Order.fromJson(data);
    }
    throw Exception('Invalid order response');
  }

  /// Metrics + recent orders for seller dashboard (403 if not approved).
  Future<Map<String, dynamic>> fetchSellerDashboardStats() async {
    final response = await _api.get(AppConstants.sellerDashboardStatsEndpoint);
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return data;
    }
    return {};
  }

  /// Returns tracking payload or throws [DioException] (e.g. 404 = delivery not started).
  Future<Map<String, dynamic>> trackDelivery(String orderNumber) async {
    final path =
        '${AppConstants.deliveryTrackPrefix}${Uri.encodeComponent(orderNumber)}/';
    final response = await _api.get(path);
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return data;
    }
    return {};
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

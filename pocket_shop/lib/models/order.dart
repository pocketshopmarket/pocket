import 'dart:convert';

class _OrderInstructionParseResult {
  final String cleanedInstructions;
  final Map<String, dynamic>? metadata;

  const _OrderInstructionParseResult({
    required this.cleanedInstructions,
    required this.metadata,
  });
}

_OrderInstructionParseResult _parseOrderInstructions(String rawInstructions) {
  final text = rawInstructions.trim();
  if (text.isEmpty) {
    return const _OrderInstructionParseResult(
      cleanedInstructions: '',
      metadata: null,
    );
  }

  final reg = RegExp(r'\[PS_META\](.*?)\[/PS_META\]');
  final match = reg.firstMatch(text);
  if (match == null) {
    return _OrderInstructionParseResult(
      cleanedInstructions: text,
      metadata: null,
    );
  }

  Map<String, dynamic>? meta;
  final payload = match.group(1)?.trim();
  if (payload != null && payload.isNotEmpty) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        meta = decoded;
      } else if (decoded is Map) {
        meta = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Ignore malformed metadata and preserve original note content.
    }
  }

  final cleaned = text.replaceFirst(reg, '').trim();
  return _OrderInstructionParseResult(
    cleanedInstructions: cleaned,
    metadata: meta,
  );
}

class OrderItemLine {
  final int id;
  final int productId;
  final String productName;
  final int quantity;
  final double price;
  final double subtotal;

  OrderItemLine({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.price,
    required this.subtotal,
  });

  factory OrderItemLine.fromJson(Map<String, dynamic> json) {
    return OrderItemLine(
      id: json['id'] as int,
      productId: json['product'] as int,
      productName: json['product_name']?.toString() ?? '',
      quantity: json['quantity'] as int,
      price: double.parse(json['price'].toString()),
      subtotal: double.parse(json['subtotal'].toString()),
    );
  }
}

class Order {
  final int id;
  final String orderNumber;
  final int buyerId;
  final String? buyerName;
  final int sellerId;
  final String? sellerName;
  final double totalPrice;
  final String status;
  final String deliveryAddress;
  final String specialInstructions;
  final String fulfillmentType;
  final double? quotedDeliveryFee;
  final double? quotedDistanceKm;
  final int? quotedEtaMinutes;
  final double? deliveryLat;
  final double? deliveryLng;
  final String? pickupTimeSlot;
  final int? paymentMethodId;
  final int? deliveryAssignmentId;
  final String paymentProviderSnapshot;
  final String paymentAccountSnapshot;
  final List<OrderRating> ratings;
  final List<OrderItemLine> items;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? sellerPhone;
  final String? buyerPhone;
  final String? sellerShopName;
  final String? sellerShopLocation;
  final double? sellerShopLat;
  final double? sellerShopLng;
  /// null = no refund request yet. Non-null = status of the existing request.
  final String? refundRequestStatus;
  /// Non-null when the order was cancelled and a refund transaction was created.
  final CancellationRefund? cancellationRefund;

  Order({
    required this.id,
    required this.orderNumber,
    required this.buyerId,
    this.buyerName,
    required this.sellerId,
    this.sellerName,
    required this.totalPrice,
    required this.status,
    required this.deliveryAddress,
    required this.specialInstructions,
    this.fulfillmentType = 'delivery',
    this.quotedDeliveryFee,
    this.quotedDistanceKm,
    this.quotedEtaMinutes,
    this.deliveryLat,
    this.deliveryLng,
    this.pickupTimeSlot,
    this.paymentMethodId,
    this.deliveryAssignmentId,
    this.paymentProviderSnapshot = '',
    this.paymentAccountSnapshot = '',
    this.ratings = const [],
    required this.items,
    required this.createdAt,
    required this.updatedAt,
    this.sellerPhone,
    this.buyerPhone,
    this.sellerShopName,
    this.sellerShopLocation,
    this.sellerShopLat,
    this.sellerShopLng,
    this.refundRequestStatus,
    this.cancellationRefund,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
            .map((e) => OrderItemLine.fromJson(e as Map<String, dynamic>))
            .toList()
        : <OrderItemLine>[];
    final rawRatings = json['ratings'];
    final ratings = rawRatings is List
        ? rawRatings
            .map((e) => OrderRating.fromJson(e as Map<String, dynamic>))
            .toList()
        : <OrderRating>[];

    final rawInstructions = json['special_instructions']?.toString() ?? '';
    final parsedInstructions = _parseOrderInstructions(rawInstructions);
    final meta = parsedInstructions.metadata;
    final fulfillmentType =
        json['fulfillment_type']?.toString() ??
        meta?['fulfillment_type']?.toString() ??
        'delivery';

    return Order(
      id: json['id'] as int,
      orderNumber: json['order_number']?.toString() ?? '',
      buyerId: json['buyer'] as int,
      buyerName: json['buyer_name']?.toString(),
      sellerId: json['seller'] as int,
      sellerName: json['seller_name']?.toString(),
      totalPrice: double.parse(json['total_price'].toString()),
      status: json['status']?.toString() ?? 'pending',
      deliveryAddress: json['delivery_address']?.toString() ?? '',
      specialInstructions: parsedInstructions.cleanedInstructions,
      fulfillmentType: fulfillmentType,
      quotedDeliveryFee: double.tryParse((json['quoted_delivery_fee'] ?? meta?['quoted_delivery_fee'] ?? '').toString()),
      quotedDistanceKm: double.tryParse((json['quoted_distance_km'] ?? meta?['quoted_distance_km'] ?? '').toString()),
      quotedEtaMinutes: int.tryParse((json['quoted_eta_minutes'] ?? meta?['quoted_eta_minutes'] ?? '').toString()),
      deliveryLat: double.tryParse((json['delivery_lat'] ?? meta?['delivery_lat'] ?? '').toString()),
      deliveryLng: double.tryParse((json['delivery_lng'] ?? meta?['delivery_lng'] ?? '').toString()),
      pickupTimeSlot: json['pickup_time_slot']?.toString() ??
          meta?['pickup_time_slot']?.toString(),
      paymentMethodId: json['payment_method_id'] as int?,
      deliveryAssignmentId: json['delivery_assignment_id'] as int?,
      paymentProviderSnapshot: json['payment_provider_snapshot']?.toString() ?? '',
      paymentAccountSnapshot: json['payment_account_snapshot']?.toString() ?? '',
      ratings: ratings,
      items: items,
      createdAt: DateTime.parse(json['created_at'].toString()),
      updatedAt: DateTime.parse(json['updated_at'].toString()),
      sellerPhone: json['seller_phone']?.toString(),
      buyerPhone: json['buyer_phone']?.toString(),
      sellerShopName: json['seller_shop_name']?.toString(),
      sellerShopLocation: json['seller_shop_location']?.toString(),
      sellerShopLat: double.tryParse((json['seller_shop_lat'] ?? '').toString()),
      sellerShopLng: double.tryParse((json['seller_shop_lng'] ?? '').toString()),
      refundRequestStatus: json['refund_request_status']?.toString(),
      cancellationRefund: json['cancellation_refund'] != null
          ? CancellationRefund.fromJson(
              Map<String, dynamic>.from(json['cancellation_refund'] as Map))
          : null,
    );
  }

  String get statusLabel {
    switch (status) {
      case 'pending':         return 'Pending';
      case 'payment_pending': return 'Payment pending';
      case 'accepted':        return 'Accepted';
      case 'preparing':       return 'Preparing';
      case 'out_for_delivery': return 'Out for delivery';
      case 'delivered':       return 'Delivered';
      case 'cancelled':       return 'Cancelled';
      default:                return status;
    }
  }

  bool get isPickup => fulfillmentType == 'pickup';
  bool get isDelivery => !isPickup;
}

class CancellationRefund {
  final String status;
  final double amount;

  const CancellationRefund({required this.status, required this.amount});

  factory CancellationRefund.fromJson(Map<String, dynamic> json) {
    return CancellationRefund(
      status: json['status']?.toString() ?? 'pending',
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0,
    );
  }

  String get label {
    switch (status) {
      case 'completed': return 'Refund sent';
      case 'pending':   return 'Refund processing';
      case 'failed':    return 'Refund failed';
      default:          return 'Refund $status';
    }
  }
}

class OrderRating {
  final int id;
  final String targetRole;
  final int score;
  final String comment;
  final String? authorName;

  OrderRating({
    required this.id,
    required this.targetRole,
    required this.score,
    required this.comment,
    this.authorName,
  });

  factory OrderRating.fromJson(Map<String, dynamic> json) {
    return OrderRating(
      id: json['id'] as int,
      targetRole: json['target_role']?.toString() ?? '',
      score: json['score'] as int? ?? 0,
      comment: json['comment']?.toString() ?? '',
      authorName: json['author_name']?.toString(),
    );
  }
}

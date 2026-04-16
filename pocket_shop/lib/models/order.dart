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
  final String paymentProviderSnapshot;
  final String paymentAccountSnapshot;
  final List<OrderRating> ratings;
  final List<OrderItemLine> items;
  final DateTime createdAt;
  final DateTime updatedAt;

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
    this.paymentProviderSnapshot = '',
    this.paymentAccountSnapshot = '',
    this.ratings = const [],
    required this.items,
    required this.createdAt,
    required this.updatedAt,
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
      quotedDeliveryFee: (json['quoted_delivery_fee'] as num?)?.toDouble() ??
          (meta?['quoted_delivery_fee'] as num?)?.toDouble(),
      quotedDistanceKm: (json['quoted_distance_km'] as num?)?.toDouble() ??
          (meta?['quoted_distance_km'] as num?)?.toDouble(),
      quotedEtaMinutes: (json['quoted_eta_minutes'] as num?)?.toInt() ??
          (meta?['quoted_eta_minutes'] as num?)?.toInt(),
      deliveryLat: (json['delivery_lat'] as num?)?.toDouble() ??
          (meta?['delivery_lat'] as num?)?.toDouble(),
      deliveryLng: (json['delivery_lng'] as num?)?.toDouble() ??
          (meta?['delivery_lng'] as num?)?.toDouble(),
      pickupTimeSlot: json['pickup_time_slot']?.toString() ??
          meta?['pickup_time_slot']?.toString(),
      paymentMethodId: json['payment_method_id'] as int?,
      paymentProviderSnapshot: json['payment_provider_snapshot']?.toString() ?? '',
      paymentAccountSnapshot: json['payment_account_snapshot']?.toString() ?? '',
      ratings: ratings,
      items: items,
      createdAt: DateTime.parse(json['created_at'].toString()),
      updatedAt: DateTime.parse(json['updated_at'].toString()),
    );
  }

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'preparing':
        return 'Preparing';
      case 'out_for_delivery':
        return 'Out for delivery';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  bool get isPickup => fulfillmentType == 'pickup';
  bool get isDelivery => !isPickup;
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

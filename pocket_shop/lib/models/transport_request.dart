class TransportRequest {
  final int id;
  final int buyerId;
  final String? buyerName;
  final int sellerId;
  final String? sellerName;
  final int productId;
  final String? productName;
  final double? productPrice;
  final String? productImageUrl;
  final int quantity;
  final String deliveryAddress;
  final double? deliveryLat;
  final double? deliveryLng;
  final double? distanceKm;
  final String status;
  final String statusDisplay;
  final String proposedMethod;
  final double? proposedFee;
  final String declineReason;
  final String? orderNumber;
  final DateTime expiresAt;
  final DateTime? respondedAt;
  final DateTime? decidedAt;
  final DateTime createdAt;

  const TransportRequest({
    required this.id,
    required this.buyerId,
    this.buyerName,
    required this.sellerId,
    this.sellerName,
    required this.productId,
    this.productName,
    this.productPrice,
    this.productImageUrl,
    required this.quantity,
    required this.deliveryAddress,
    this.deliveryLat,
    this.deliveryLng,
    this.distanceKm,
    required this.status,
    required this.statusDisplay,
    this.proposedMethod = '',
    this.proposedFee,
    this.declineReason = '',
    this.orderNumber,
    required this.expiresAt,
    this.respondedAt,
    this.decidedAt,
    required this.createdAt,
  });

  factory TransportRequest.fromJson(Map<String, dynamic> json) {
    return TransportRequest(
      id: json['id'] as int,
      buyerId: json['buyer'] as int,
      buyerName: json['buyer_name']?.toString(),
      sellerId: json['seller'] as int,
      sellerName: json['seller_name']?.toString(),
      productId: json['product'] as int,
      productName: json['product_name']?.toString(),
      productPrice: double.tryParse(json['product_price']?.toString() ?? ''),
      productImageUrl: json['product_image_url']?.toString(),
      quantity: json['quantity'] as int? ?? 1,
      deliveryAddress: json['delivery_address']?.toString() ?? '',
      deliveryLat: double.tryParse(json['delivery_lat']?.toString() ?? ''),
      deliveryLng: double.tryParse(json['delivery_lng']?.toString() ?? ''),
      distanceKm: double.tryParse(json['distance_km']?.toString() ?? ''),
      status: json['status']?.toString() ?? 'pending',
      statusDisplay: json['status_display']?.toString() ??
          json['status']?.toString() ??
          'Pending',
      proposedMethod: json['proposed_method']?.toString() ?? '',
      proposedFee: double.tryParse(json['proposed_fee']?.toString() ?? ''),
      declineReason: json['decline_reason']?.toString() ?? '',
      orderNumber: json['order_number']?.toString(),
      expiresAt: DateTime.parse(json['expires_at'].toString()),
      respondedAt: DateTime.tryParse(json['responded_at']?.toString() ?? ''),
      decidedAt: DateTime.tryParse(json['decided_at']?.toString() ?? ''),
      createdAt: DateTime.parse(json['created_at'].toString()),
    );
  }

  bool get isPending => status == 'pending';
  bool get isProposed => status == 'proposed';
  bool get isDecided =>
      status == 'declined' || status == 'expired' || status == 'accepted';
}

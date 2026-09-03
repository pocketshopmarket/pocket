String? _parseTrimmedString(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  return s.isEmpty ? null : s;
}

/// A seller's public storefront — buyer-facing discovery model.
/// Mirrors `ShopPublicSerializer` (accounts/serializers.py) — deliberately
/// carries none of the verification/identity fields the seller's own
/// `SellerProfile` has, since this comes from a public, unauthenticated endpoint.
class Shop {
  final int id;
  final String shopName;
  final String? shopLogo;
  final String shopDescription;
  final String shopLocation;
  final double? shopLat;
  final double? shopLng;
  final double? distanceKm;
  final int productCount;
  final String? topCategory;
  final bool isVerified;

  Shop({
    required this.id,
    required this.shopName,
    this.shopLogo,
    this.shopDescription = '',
    required this.shopLocation,
    this.shopLat,
    this.shopLng,
    this.distanceKm,
    this.productCount = 0,
    this.topCategory,
    this.isVerified = false,
  });

  factory Shop.fromJson(Map<String, dynamic> json) {
    return Shop(
      id: json['id'] as int,
      shopName: json['shop_name']?.toString() ?? '',
      shopLogo: _parseTrimmedString(json['shop_logo']),
      shopDescription: json['shop_description']?.toString() ?? '',
      shopLocation: json['shop_location']?.toString() ?? '',
      shopLat: (json['shop_lat'] as num?)?.toDouble(),
      shopLng: (json['shop_lng'] as num?)?.toDouble(),
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      productCount: json['product_count'] is int
          ? json['product_count'] as int
          : int.tryParse('${json['product_count']}') ?? 0,
      topCategory: _parseTrimmedString(json['top_category']),
      isVerified: json['is_verified'] == true,
    );
  }
}

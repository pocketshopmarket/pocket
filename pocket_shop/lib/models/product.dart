String? _parseImageUrl(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  return s.isEmpty ? null : s;
}

List<String> _parseImagesFromJson(Map<String, dynamic> json) {
  final raw = json['images'];
  if (raw is List) {
    final out = <String>[];
    for (final e in raw) {
      if (e is Map<String, dynamic> && e['url'] != null) {
        final u = e['url'].toString().trim();
        if (u.isNotEmpty) out.add(u);
      } else if (e is Map && e['url'] != null) {
        final u = e['url'].toString().trim();
        if (u.isNotEmpty) out.add(u);
      } else if (e is String && e.trim().isNotEmpty) {
        out.add(e.trim());
      }
    }
    if (out.isNotEmpty) return out;
  }
  final legacy = _parseImageUrl(json['image_url']);
  if (legacy != null) return [legacy];
  return const [];
}

class Product {
  final int id;
  final String name;
  final String description;
  final double price;
  final String category;
  final String quality;
  final int sellerId;
  final String? sellerName;
  final String? sellerPhone;
  final int stockQuantity;
  final List<String> imageUrls;
  final bool isAvailable;
  final bool isInStock;
  final double reviewAverage;
  final int reviewCount;
  final List<ProductVariant> variants;
  final DateTime createdAt;

  Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.category,
    this.quality = 'new',
    required this.sellerId,
    this.sellerName,
    this.sellerPhone,
    required this.stockQuantity,
    this.imageUrls = const [],
    required this.isAvailable,
    required this.isInStock,
    this.reviewAverage = 0,
    this.reviewCount = 0,
    this.variants = const [],
    required this.createdAt,
  });

  /// First image for grid thumbnails and legacy call sites.
  String? get imageUrl => imageUrls.isEmpty ? null : imageUrls.first;

  /// Build from a server cart line (`CartItemSerializer`); seller may be unknown (0).
  factory Product.fromCartLine(Map<String, dynamic> json) {
    final thumb = _parseImageUrl(json['product_image_url']);
    return Product(
      id: json['product'] as int,
      name: json['product_name']?.toString() ?? '',
      description: '',
      price: double.parse(json['product_price'].toString()),
      category: 'other',
      sellerId: json['seller_id'] is int ? json['seller_id'] as int : int.tryParse('${json['seller_id']}') ?? 0,
      stockQuantity: 0,
      imageUrls: thumb != null ? [thumb] : const [],
      isAvailable: true,
      isInStock: true,
      reviewAverage: 0,
      reviewCount: 0,
      variants: const [],
      createdAt: DateTime.now(),
    );
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as int,
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      price: double.parse(json['price'].toString()),
      category: json['category']?.toString() ?? 'other',
      quality: json['quality']?.toString() ?? 'new',
      sellerId: json['seller'] as int,
      sellerName: json['seller_name']?.toString(),
      sellerPhone: json['seller_phone']?.toString(),
      stockQuantity: json['stock_quantity'] is int ? json['stock_quantity'] as int : int.tryParse('${json['stock_quantity']}') ?? 0,
      imageUrls: _parseImagesFromJson(json),
      isAvailable: json['is_available'] ?? true,
      isInStock: json['is_in_stock'] ?? true,
      reviewAverage: (json['review_avg'] as num?)?.toDouble() ?? 0,
      reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
      variants: (json['variants'] is List)
          ? (json['variants'] as List)
              .map((e) => ProductVariant.fromJson(e as Map<String, dynamic>))
              .toList()
          : const [],
      createdAt: DateTime.parse(json['created_at'].toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'price': price,
      'category': category,
      'quality': quality,
      'stock_quantity': stockQuantity,
      'is_available': isAvailable,
    };
  }

  /// Human-readable quality for listings (matches buyer detail labels).
  String get qualityDisplayLabel {
    const labels = {
      'new': 'New',
      'like_new': 'Like new',
      'good': 'Good',
      'fair': 'Fair',
      'used': 'Used',
    };
    return labels[quality] ?? quality;
  }
}

class ProductVariant {
  final int id;
  final String name;
  final String value;
  final String sku;
  final int stockQuantity;

  const ProductVariant({
    required this.id,
    required this.name,
    required this.value,
    required this.sku,
    required this.stockQuantity,
  });

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      id: json['id'] as int,
      name: json['name']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
      sku: json['sku']?.toString() ?? '',
      stockQuantity: (json['stock_quantity'] as num?)?.toInt() ?? 0,
    );
  }
}

class ProductReview {
  final int id;
  final int rating;
  final String comment;
  final String? authorName;
  final bool isVerifiedPurchase;
  final DateTime createdAt;

  const ProductReview({
    required this.id,
    required this.rating,
    required this.comment,
    this.authorName,
    required this.isVerifiedPurchase,
    required this.createdAt,
  });

  factory ProductReview.fromJson(Map<String, dynamic> json) {
    return ProductReview(
      id: json['id'] as int,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      comment: json['comment']?.toString() ?? '',
      authorName: json['author_name']?.toString(),
      isVerifiedPurchase: json['is_verified_purchase'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

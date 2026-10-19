/// A seller's own "promote your shop" banner request, including the
/// status/price fields the public buyer-facing banner feed never exposes.
class SellerBanner {
  final int id;
  final String title;
  final String subtitle;
  final String status;
  final String pricePaid;
  final int durationDays;
  final String? imageUrl;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime createdAt;

  const SellerBanner({
    required this.id,
    required this.title,
    this.subtitle = '',
    required this.status,
    required this.pricePaid,
    required this.durationDays,
    this.imageUrl,
    this.startsAt,
    this.endsAt,
    required this.createdAt,
  });

  factory SellerBanner.fromJson(Map<String, dynamic> json) {
    return SellerBanner(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      status: json['status'] as String? ?? 'draft',
      pricePaid: json['price_paid']?.toString() ?? '0.00',
      durationDays: json['duration_days'] as int? ?? 0,
      imageUrl: json['image_url'] as String?,
      startsAt: json['starts_at'] != null ? DateTime.tryParse(json['starts_at'] as String) : null,
      endsAt: json['ends_at'] != null ? DateTime.tryParse(json['ends_at'] as String) : null,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  String get statusLabel {
    switch (status) {
      case 'pending_payment':
        return 'Awaiting payment';
      case 'pending_review':
        return 'Awaiting staff review';
      case 'active':
        return 'Live';
      case 'rejected':
        return 'Rejected';
      case 'expired':
        return 'Expired';
      default:
        return status;
    }
  }
}

import 'package:flutter/material.dart';

/// A promotional banner displayed on the buyer home screen.
class PromoBanner {
  final int id;
  final String title;
  final String subtitle;
  final String ctaText;
  final String bgColor;
  final String iconName;
  final String? imageUrl;
  final String actionType;
  final String actionValue;

  const PromoBanner({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.ctaText = 'Shop now',
    this.bgColor = '#F97316',
    this.iconName = 'shopping_bag_outlined',
    this.imageUrl,
    this.actionType = 'none',
    this.actionValue = '',
  });

  factory PromoBanner.fromJson(Map<String, dynamic> json) {
    return PromoBanner(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      ctaText: json['cta_text'] as String? ?? 'Shop now',
      bgColor: json['bg_color'] as String? ?? '#F97316',
      iconName: json['icon_name'] as String? ?? 'shopping_bag_outlined',
      imageUrl: json['image_url'] as String?,
      actionType: json['action_type'] as String? ?? 'none',
      actionValue: json['action_value'] as String? ?? '',
    );
  }

  /// Parse hex color string (e.g. "#F97316") to a Flutter [Color].
  Color get backgroundColor {
    final hex = bgColor.replaceFirst('#', '');
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    return const Color(0xFFF97316); // fallback orange
  }

  /// Map icon_name strings to Flutter IconData.
  IconData get icon {
    switch (iconName) {
      case 'shopping_bag_outlined':
        return Icons.shopping_bag_outlined;
      case 'local_offer_outlined':
        return Icons.local_offer_outlined;
      case 'storefront_outlined':
        return Icons.storefront_outlined;
      case 'flash_on_outlined':
        return Icons.flash_on_outlined;
      case 'star_outlined':
        return Icons.star_outline;
      case 'favorite_outlined':
        return Icons.favorite_outline;
      case 'celebration_outlined':
        return Icons.celebration_outlined;
      default:
        return Icons.shopping_bag_outlined;
    }
  }

  /// Default banners to show when the API is unavailable.
  static const List<PromoBanner> defaults = [
    PromoBanner(
      id: -1,
      title: 'Fresh picks',
      subtitle: 'Delivered faster',
      ctaText: 'Shop now',
      bgColor: '#F97316',
      iconName: 'shopping_bag_outlined',
      actionType: 'none',
    ),
    PromoBanner(
      id: -2,
      title: 'Trending deals',
      subtitle: 'Save on essentials',
      ctaText: 'View offers',
      bgColor: '#3B82F6',
      iconName: 'shopping_bag_outlined',
      actionType: 'none',
    ),
  ];
}

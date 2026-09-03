import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/shop.dart';

/// Reusable shop tile for the buyer Home "Near Me" and "All Shops" sections.
class ShopCard extends StatelessWidget {
  const ShopCard({super.key, required this.shop, required this.onTap});

  final Shop shop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.divider.withValues(alpha: 0.9)),
          boxShadow: const [
            BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: SizedBox(
                height: 84,
                width: double.infinity,
                child: shop.shopLogo != null
                    ? CachedNetworkImage(
                        imageUrl: shop.shopLogo!,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => _fallbackIcon(),
                        placeholder: (context, url) => Container(color: AppTheme.divider.withValues(alpha: 0.3)),
                      )
                    : _fallbackIcon(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          shop.shopName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      if (shop.isVerified) ...[
                        const SizedBox(width: 3),
                        const Icon(Icons.verified_rounded, size: 13, color: AppTheme.success),
                      ],
                    ],
                  ),
                  if (shop.topCategory != null) ...[
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryCyan.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        shop.topCategory!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.darkCyan,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (shop.distanceKm != null) ...[
                        const Icon(Icons.place_outlined, size: 11, color: AppTheme.textSecondary),
                        const SizedBox(width: 2),
                        Text(
                          '${shop.distanceKm!.toStringAsFixed(1)} km',
                          style: const TextStyle(fontSize: 10.5, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(width: 8),
                      ],
                      const Icon(Icons.inventory_2_outlined, size: 11, color: AppTheme.textSecondary),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          '${shop.productCount} item${shop.productCount == 1 ? '' : 's'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, color: AppTheme.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackIcon() {
    return Container(
      color: AppTheme.divider.withValues(alpha: 0.3),
      alignment: Alignment.center,
      child: const Icon(Icons.storefront_outlined, size: 30, color: AppTheme.textSecondary),
    );
  }
}

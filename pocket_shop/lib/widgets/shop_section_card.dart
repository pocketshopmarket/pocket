import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/product.dart';
import '../models/shop.dart';
import 'product_list_thumbnail.dart';

/// A shop, presented as a card: name/badges up top, then a horizontal strip
/// of a few of its actual products underneath — real photos throughout,
/// never a single guessed shop-level image. Used for both "Shops near you"
/// and "All shops" on buyer Home, replacing the old bare-tile grid.
class ShopSectionCard extends StatelessWidget {
  const ShopSectionCard({
    super.key,
    required this.shop,
    required this.onOpenShop,
    required this.onProductTap,
  });

  final Shop shop;
  final VoidCallback onOpenShop;
  final void Function(Product product) onProductTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider.withValues(alpha: 0.9)),
        boxShadow: const [
          BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpenShop,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: shop.shopLogo != null
                          ? CachedNetworkImage(
                              imageUrl: shop.shopLogo!,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) => _fallbackIcon(),
                              placeholder: (context, url) =>
                                  Container(color: AppTheme.divider.withValues(alpha: 0.3)),
                            )
                          : _fallbackIcon(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                shop.shopName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            if (shop.isVerified) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.verified_rounded, size: 14, color: AppTheme.success),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            if (shop.topCategory != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryCyan.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  shop.topCategory!,
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.darkCyan,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                shop.distanceKm != null
                                    ? '${shop.productCount} item${shop.productCount == 1 ? '' : 's'} · ${shop.distanceKm!.toStringAsFixed(1)} km'
                                    : '${shop.productCount} item${shop.productCount == 1 ? '' : 's'}',
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
                  const SizedBox(width: 4),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'See all',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppTheme.darkCyan),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 16, color: AppTheme.darkCyan),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (shop.productsPreview.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text(
                'No products listed yet.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            )
          else
            SizedBox(
              height: 148,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                scrollDirection: Axis.horizontal,
                itemCount: shop.productsPreview.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final product = shop.productsPreview[index];
                  return _PreviewThumb(
                    product: product,
                    onTap: () => onProductTap(product),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _fallbackIcon() {
    return Container(
      color: AppTheme.divider.withValues(alpha: 0.3),
      alignment: Alignment.center,
      child: const Icon(Icons.storefront_outlined, size: 20, color: AppTheme.textSecondary),
    );
  }
}

class _PreviewThumb extends StatelessWidget {
  const _PreviewThumb({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 96,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 96,
                height: 96,
                child: ProductListThumbnail(product: product, compactPlaceholder: true),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: AppTheme.textPrimary),
            ),
            Text(
              'ZMW ${product.price.toStringAsFixed(2)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

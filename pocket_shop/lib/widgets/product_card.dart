import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/product.dart';
import 'product_list_thumbnail.dart';

/// Shared product tile — promoted from buyer_home_screen.dart's former
/// private `_ProductCard` so buyer_search_screen.dart's Trending/Recommended
/// sections can reuse it instead of a third copy of this markup.
class ProductCard extends StatelessWidget {
  final Product product;
  final bool inStock;
  final bool isFavorite;
  final VoidCallback onAdd;
  final VoidCallback onToggleFavorite;
  final VoidCallback onCardTap;

  const ProductCard({
    super.key,
    required this.product,
    required this.inStock,
    required this.isFavorite,
    required this.onAdd,
    required this.onToggleFavorite,
    required this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 165;
        final imageHeight = compact ? 108.0 : 124.0;
        final nameSize = compact ? 12.0 : 13.0;
        final priceSize = compact ? 14.0 : 15.0;
        final buttonHeight = compact ? 30.0 : 32.0;
        return InkWell(
          onTap: onCardTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.divider.withValues(alpha: 0.9),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0D000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(14),
                      ),
                      child: SizedBox(
                        height: imageHeight,
                        width: double.infinity,
                        child: ProductListThumbnail(
                          product: product,
                          compactPlaceholder: true,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: InkWell(
                        onTap: onToggleFavorite,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppTheme.divider),
                          ),
                          child: Icon(
                            isFavorite ? Icons.favorite : Icons.favorite_border,
                            size: 15,
                            color: isFavorite
                                ? AppTheme.error
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: nameSize,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          product.qualityDisplayLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.darkCyan,
                          ),
                        ),
                        if (product.sellerName != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.storefront_outlined, size: 10, color: AppTheme.textSecondary),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  product.sellerName!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 2),
                        Text(
                          'ZMW ${product.price.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: priceSize,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        if (product.reviewCount > 0)
                          Row(
                            children: [
                              const Icon(Icons.star_rounded, size: 11, color: Color(0xFFF59E0B)),
                              const SizedBox(width: 2),
                              Text(
                                '${product.reviewAverage.toStringAsFixed(1)} (${product.reviewCount})',
                                style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        const Spacer(),
                        SizedBox(
                          width: double.infinity,
                          height: buttonHeight,
                          child: ElevatedButton(
                            onPressed: inStock ? onAdd : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: inStock
                                  ? AppTheme.primaryCyan
                                  : AppTheme.divider,
                              foregroundColor: inStock
                                  ? Colors.white
                                  : AppTheme.textSecondary,
                              elevation: 0,
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: inStock
                                ? const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.add_shopping_cart, size: 14),
                                      SizedBox(width: 4),
                                      Text(
                                        'Add to cart',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  )
                                : const Text(
                                    'Unavailable',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

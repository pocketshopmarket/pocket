import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../models/product.dart';
import 'product_list_thumbnail.dart';

/// The one product tile used by every product grid and rail.
///
/// The image flexes to fill whatever height the parent gives it while the
/// text block below is a fixed height (names always reserve two lines), so
/// tiles in the same grid row line up exactly. Grids should size cells with
/// [ProductCard.gridExtent].
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

  static const double _bodyHeight = 98;

  /// Cell height for a grid column of [cellWidth]: a square image + text.
  static double gridExtent(double cellWidth) => cellWidth + _bodyHeight;

  @override
  Widget build(BuildContext context) {
    final showQuality = product.quality != 'new';
    final rating = product.reviewCount > 0
        ? '★ ${product.reviewAverage.toStringAsFixed(1)}'
        : null;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onCardTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ProductListThumbnail(product: product, compactPlaceholder: true),
                    if (showQuality || !inStock)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: _Badge(label: inStock ? product.qualityDisplayLabel : 'Sold out'),
                      ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _RoundIconButton(
                        onTap: onToggleFavorite,
                        tooltip: isFavorite ? 'Remove from wishlist' : 'Save to wishlist',
                        child: Icon(
                          isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          size: 16,
                          color: isFavorite ? AppTheme.accentOrange : AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    if (inStock)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Tooltip(
                          message: 'Add to cart',
                          child: Material(
                            color: AppTheme.primaryCyan,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              onTap: onAdd,
                              borderRadius: BorderRadius.circular(10),
                              child: const SizedBox.square(
                                dimension: 34,
                                child: Icon(Icons.add_rounded, color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: _bodyHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ZMW ${product.price.toStringAsFixed(2)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.display(
                          fontSize: 15,
                          color: inStock ? AppTheme.textPrimary : AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      SizedBox(
                        height: 34,
                        child: Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: product.sellerName == null
                            ? null
                            : () => context.push('/buyer/shop-details?id=${product.sellerId}'),
                        child: Text(
                          [
                            ?rating,
                            if (product.sellerName != null) product.sellerName!,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(fontSize: 11.5, color: AppTheme.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.textPrimary.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTheme.body(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.onTap, required this.child, required this.tooltip});

  final VoidCallback onTap;
  final Widget child;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox.square(dimension: 30, child: Center(child: child)),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/product.dart';

/// Primary gallery image for list/grid/cart: loading and error handling, optional multi-photo badge.
class ProductListThumbnail extends StatelessWidget {
  const ProductListThumbnail({
    super.key,
    required this.product,
    this.showGalleryCountBadge = true,
    this.compactPlaceholder = false,
  });

  final Product product;
  final bool showGalleryCountBadge;
  final bool compactPlaceholder;

  @override
  Widget build(BuildContext context) {
    final primary = product.imageUrl;
    final n = product.imageUrls.length;

    Widget placeholder() {
      return ColoredBox(
        color: AppTheme.surfaceWhite,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.photo_outlined,
                size: compactPlaceholder ? 22 : 28,
                color: AppTheme.textSecondary.withValues(alpha: 0.85),
              ),
              if (!compactPlaceholder) ...[
                const SizedBox(height: 4),
                Text(
                  'No photo',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondary.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    Widget errorState() {
      return ColoredBox(
        color: AppTheme.surfaceWhite,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.broken_image_outlined,
                size: compactPlaceholder ? 22 : 26,
                color: AppTheme.textSecondary,
              ),
              if (!compactPlaceholder) ...[
                const SizedBox(height: 4),
                Text(
                  'Could not load',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.textSecondary.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (primary != null && primary.isNotEmpty)
          Image.network(
            primary,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return ColoredBox(
                color: AppTheme.surfaceWhite,
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primaryCyan.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              );
            },
            errorBuilder: (context, _, _) => errorState(),
          )
        else
          placeholder(),
        if (showGalleryCountBadge && n > 1)
          Positioned(
            right: 6,
            bottom: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.collections_outlined, size: 11, color: Colors.white),
                    const SizedBox(width: 3),
                    Text(
                      '$n',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

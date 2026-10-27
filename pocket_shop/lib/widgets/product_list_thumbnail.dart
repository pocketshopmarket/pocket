import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/product.dart';
import 'shimmer_loading.dart';

/// Pixel width to decode a photo at for a box this size. Sellers upload
/// full-resolution photos; decoding those for a small tile wastes memory and
/// stutters scrolling. The 1.35 headroom lets a landscape photo still fill a
/// square box under BoxFit.cover without going soft.
int? decodeWidthFor(BuildContext context, BoxConstraints constraints) {
  final side = constraints.maxWidth.isFinite && constraints.maxHeight.isFinite
      ? (constraints.maxWidth > constraints.maxHeight ? constraints.maxWidth : constraints.maxHeight)
      : (constraints.maxWidth.isFinite ? constraints.maxWidth : null);
  if (side == null || side <= 0) return null;
  return (side * MediaQuery.devicePixelRatioOf(context) * 1.35).round();
}

/// Primary gallery image for list/grid/cart: cached on disk, decoded at display
/// size, shimmer while loading, optional multi-photo badge.
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
          LayoutBuilder(
            builder: (context, constraints) {
              return CachedNetworkImage(
                imageUrl: primary,
                fit: BoxFit.cover,
                memCacheWidth: decodeWidthFor(context, constraints),
                fadeInDuration: const Duration(milliseconds: 220),
                placeholder: (_, _) => const ShimmerFill(),
                errorWidget: (_, _, _) => errorState(),
              );
            },
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

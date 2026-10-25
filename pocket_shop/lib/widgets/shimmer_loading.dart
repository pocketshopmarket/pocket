import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../core/theme/app_theme.dart';

/// Shared shimmer wrapper — same base/highlight everywhere so every skeleton
/// in the app animates identically instead of each screen picking its own.
class AppShimmer extends StatelessWidget {
  const AppShimmer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppTheme.divider.withValues(alpha: 0.6),
      highlightColor: AppTheme.divider.withValues(alpha: 0.15),
      period: const Duration(milliseconds: 1400),
      child: child,
    );
  }
}

/// A plain rounded-rect placeholder block — the building piece every
/// skeleton below is made of.
class _Block extends StatelessWidget {
  const _Block({this.width, this.height = 12, this.radius = 6});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Skeleton matching [ShopSectionCard]'s exact layout (logo, name line,
/// category pill, product-thumbnail strip) so the loading state previews
/// the shape of what's coming instead of a generic spinner.
class ShopCardShimmer extends StatelessWidget {
  const ShopCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider.withValues(alpha: 0.9)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _Block(width: 40, height: 40, radius: 10),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Block(width: 120, height: 13),
                        const SizedBox(height: 8),
                        _Block(width: 90, height: 10),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 148,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                scrollDirection: Axis.horizontal,
                itemCount: 3,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, _) => const SizedBox(
                  width: 96,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Block(width: 96, height: 96, radius: 10),
                      SizedBox(height: 6),
                      _Block(width: 70, height: 9),
                      SizedBox(height: 4),
                      _Block(width: 50, height: 10),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row of pill-shaped placeholders matching the shop-type filter chips.
class ShopTypeChipsShimmer extends StatelessWidget {
  const ShopTypeChipsShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 5,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => _Block(width: i == 0 ? 50 : 90, height: 36, radius: 18),
        ),
      ),
    );
  }
}

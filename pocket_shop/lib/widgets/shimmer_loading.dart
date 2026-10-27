import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../core/theme/app_theme.dart';

/// Shared shimmer wrapper — same base/highlight everywhere so every skeleton
/// in the app animates identically instead of each screen picking its own.
///
/// Shimmer recolors everything it wraps, so wrap only the placeholder blocks,
/// never the card behind them, or the whole card turns into one blob.
class AppShimmer extends StatelessWidget {
  const AppShimmer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE9EBEF),
      highlightColor: const Color(0xFFF6F7F9),
      period: const Duration(milliseconds: 1400),
      child: child,
    );
  }
}

/// A rounded placeholder block — the piece every skeleton is made of.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 12, this.radius = 6});

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

/// Fills its box with shimmer: the placeholder for any image still loading.
class ShimmerFill extends StatelessWidget {
  const ShimmerFill({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppShimmer(child: ColoredBox(color: Colors.white, child: SizedBox.expand()));
  }
}

BoxDecoration _card(double radius) => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppTheme.divider),
    );

/// Skeleton matching [ShopSectionCard]: logo, name line, tag, product strip.
class ShopCardShimmer extends StatelessWidget {
  const ShopCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _card(16),
      child: AppShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 10, 10),
              child: Row(
                children: [
                  SkeletonBox(width: 52, height: 52, radius: 14),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 150, height: 13),
                        SizedBox(height: 8),
                        SkeletonBox(width: 100, height: 10),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 148,
              child: ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                scrollDirection: Axis.horizontal,
                itemCount: 4,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, _) => const SizedBox(
                  width: 96,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 96, height: 96, radius: 10),
                      SizedBox(height: 6),
                      SkeletonBox(width: 70, height: 9),
                      SizedBox(height: 5),
                      SkeletonBox(width: 50, height: 10),
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
          physics: const NeverScrollableScrollPhysics(),
          scrollDirection: Axis.horizontal,
          itemCount: 5,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => SkeletonBox(width: i == 0 ? 50 : 90, height: 36, radius: 18),
        ),
      ),
    );
  }
}

/// Skeleton for one [ProductCard]: image fills the top, fixed text block below.
class ProductCardShimmer extends StatelessWidget {
  const ProductCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _card(16),
      child: const AppShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: ColoredBox(color: Colors.white)),
            SizedBox(
              height: 98,
              child: Padding(
                padding: EdgeInsets.fromLTRB(10, 10, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 66, height: 14),
                    SizedBox(height: 9),
                    SkeletonBox(height: 10),
                    SizedBox(height: 6),
                    SkeletonBox(width: 90, height: 10),
                    Spacer(),
                    SkeletonBox(width: 76, height: 9),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner-shaped placeholder for the Home carousel.
class BannerShimmer extends StatelessWidget {
  const BannerShimmer({super.key, this.height = 176});

  final double height;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(child: SkeletonBox(height: height, radius: 20));
  }
}

/// Generic list of card rows (orders, notifications, seller lists) shown in
/// place of a page spinner while the first page loads.
class ListRowsShimmer extends StatelessWidget {
  const ListRowsShimmer({
    super.key,
    this.count = 6,
    this.padding = const EdgeInsets.all(16),
    this.leading = true,
    this.rowHeight = 78,
  });

  final int count;
  final EdgeInsetsGeometry padding;
  final bool leading;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => Container(
        height: rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: _card(14),
        child: AppShimmer(
          child: Row(
            children: [
              if (leading) ...[
                const SkeletonBox(width: 44, height: 44, radius: 12),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: i.isEven ? 150 : 120, height: 12),
                    const SizedBox(height: 9),
                    SkeletonBox(width: i.isEven ? 200 : 170, height: 10),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const SkeletonBox(width: 58, height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stacked card placeholders for detail pages, one per section height given.
class SectionsShimmer extends StatelessWidget {
  const SectionsShimmer({super.key, this.heights = const [120, 190, 150]});

  final List<double> heights;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: heights.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => Container(
        height: heights[i],
        padding: const EdgeInsets.all(16),
        decoration: _card(16),
        child: AppShimmer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(width: 130, height: 14),
              const SizedBox(height: 14),
              const SkeletonBox(height: 10),
              const SizedBox(height: 8),
              const SkeletonBox(width: 220, height: 10),
              if (heights[i] > 140) ...[
                const SizedBox(height: 8),
                const SkeletonBox(width: 180, height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

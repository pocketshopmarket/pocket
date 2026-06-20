import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../models/product.dart';
import '../../../../providers/cart_provider.dart';
import '../../../../providers/product_provider.dart';
import '../../../../providers/wishlist_provider.dart';
import '../../../../widgets/product_list_thumbnail.dart';

class BuyerWishlistScreen extends ConsumerWidget {
  const BuyerWishlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wishlist = ref.watch(wishlistProvider);
    final productState = ref.watch(productProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final wishlistNotifier = ref.read(wishlistProvider.notifier);
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 360;

    final productMap = <int, Product>{};
    for (final p in productState.trendingProducts) {
      productMap[p.id] = p;
    }
    for (final p in productState.products) {
      productMap[p.id] = p;
    }
    final items = wishlist
        .map((id) => productMap[id])
        .whereType<Product>()
        .toList();

    Widget emptyBody;
    if (wishlist.isEmpty) {
      emptyBody = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.divider),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.favorite_border_rounded, size: 42, color: AppTheme.textSecondary),
                SizedBox(height: 10),
                Text(
                  'No favorites yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
                SizedBox(height: 4),
                Text(
                  'Tap hearts on products to save them here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      emptyBody = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.divider),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inventory_2_outlined, size: 42, color: AppTheme.textSecondary),
                SizedBox(height: 10),
                Text(
                  'Items unavailable',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
                SizedBox(height: 4),
                Text(
                  'Your saved items could not be loaded. Browse the shop to find them again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(title: const Text('Wishlist')),
      body: items.isEmpty
          ? emptyBody
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
              itemCount: items.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: isCompact ? 8 : 10,
                mainAxisSpacing: 10,
                childAspectRatio: isCompact ? 0.66 : 0.7,
              ),
              itemBuilder: (_, index) {
                final product = items[index];
                final inStock = product.isAvailable && product.isInStock;
                return Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.divider),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0D000000),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () =>
                        context.push('/buyer/product-details', extra: product),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: ProductListThumbnail(
                                    product: product,
                                    compactPlaceholder: true,
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 6,
                                top: 6,
                                child: InkWell(
                                  onTap: () =>
                                      wishlistNotifier.toggle(product.id),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.95,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: AppTheme.divider,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.favorite,
                                      size: 16,
                                      color: AppTheme.error,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
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
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: AppTheme.warning,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              product.reviewAverage.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '(${product.reviewCount})',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'ZMW ${product.price.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: inStock
                                  ? () async {
                                      final err = await cartNotifier.addProduct(
                                        product,
                                      );
                                      if (!context.mounted || err == null) {
                                        return;
                                      }
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(err),
                                          backgroundColor: AppTheme.error,
                                        ),
                                      );
                                    }
                                  : null,
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppTheme.divider),
                                ),
                                child: Icon(
                                  Icons.add_shopping_cart_rounded,
                                  size: 16,
                                  color: inStock
                                      ? AppTheme.darkCyan
                                      : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

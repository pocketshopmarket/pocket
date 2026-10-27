import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../models/product.dart';
import '../../../../providers/cart_provider.dart';
import '../../../../providers/product_provider.dart';
import '../../../../providers/wishlist_provider.dart';
import '../../../../widgets/product_card.dart';
import '../../../../widgets/ui/ps_ui.dart';

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

    final Widget emptyBody = Center(
      child: wishlist.isEmpty
          ? PsEmptyState(
              icon: Icons.favorite_border_rounded,
              title: 'Nothing saved yet',
              message: 'Tap the heart on anything you like and it will wait for you here.',
              actionLabel: 'Browse products',
              onAction: () => context.go('/buyer/shop'),
            )
          : PsEmptyState(
              icon: Icons.inventory_2_outlined,
              title: "Your saved items didn't load",
              message: 'Pull down on Products to refresh, then check back here.',
              actionLabel: 'Go to Products',
              onAction: () => context.go('/buyer/shop'),
            ),
    );

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
                mainAxisSpacing: 12,
                mainAxisExtent: ProductCard.gridExtent(
                  (screenWidth - 28 - (isCompact ? 8 : 10)) / 2,
                ),
              ),
              itemBuilder: (_, index) {
                final product = items[index];
                final inStock = product.isAvailable && product.isInStock;
                return ProductCard(
                  product: product,
                  inStock: inStock,
                  isFavorite: true,
                  onToggleFavorite: () => wishlistNotifier.toggle(product.id),
                  onCardTap: () => context.push('/buyer/product-details', extra: product),
                  onAdd: () async {
                    final err = await cartNotifier.addProduct(product);
                    if (!context.mounted || err == null) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(err), backgroundColor: AppTheme.error),
                    );
                  },
                );
              },
            ),
    );
  }
}

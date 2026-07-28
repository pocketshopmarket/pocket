import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../models/product.dart';
import '../providers/cart_provider.dart';
import '../services/product_service.dart';
import 'product_list_thumbnail.dart';

/// Shown right after adding the first item to an empty cart. Checkout only
/// allows one seller per order, so this is the highest-leverage moment to
/// help the buyer fill out that single order instead of discovering the
/// one-seller limit later at checkout.
class SellerSuggestionsSheet extends ConsumerStatefulWidget {
  const SellerSuggestionsSheet({
    super.key,
    required this.sellerId,
    required this.sellerName,
    required this.products,
  });

  final int sellerId;
  final String sellerName;
  final List<Product> products;

  /// Fetches other in-stock products from [sellerId] and only opens the
  /// sheet if there's actually something to suggest — avoids interrupting
  /// the buyer with an empty sheet.
  static Future<void> showIfAvailable(
    BuildContext context, {
    required int sellerId,
    required int excludeProductId,
    required String sellerName,
  }) async {
    final products = await ProductService().fetchBySeller(
      sellerId,
      excludeProductId: excludeProductId,
    );
    if (products.isEmpty) return;
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SellerSuggestionsSheet(
        sellerId: sellerId,
        sellerName: sellerName,
        products: products,
      ),
    );
  }

  @override
  ConsumerState<SellerSuggestionsSheet> createState() => _SellerSuggestionsSheetState();
}

class _SellerSuggestionsSheetState extends ConsumerState<SellerSuggestionsSheet> {
  final Set<int> _adding = {};
  final Set<int> _added = {};

  Future<void> _add(Product product) async {
    setState(() => _adding.add(product.id));
    final err = await ref.read(cartProvider.notifier).addProduct(product);
    if (!mounted) return;
    setState(() {
      _adding.remove(product.id);
      if (err == null) _added.add(product.id);
    });
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: AppTheme.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Added! Add more from ${widget.sellerName}?',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Your order can only include items from one seller.',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 190,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.products.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final product = widget.products[index];
                    final isAdding = _adding.contains(product.id);
                    final isAdded = _added.contains(product.id);
                    return SizedBox(
                      width: 130,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 130,
                              height: 100,
                              child: ProductListThumbnail(
                                product: product,
                                compactPlaceholder: true,
                                showGalleryCountBadge: false,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'ZMW ${product.price.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.primaryCyan, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            height: 30,
                            child: OutlinedButton(
                              onPressed: isAdding || isAdded ? null : () => _add(product),
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.zero,
                                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                              child: isAdding
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Text(isAdded ? 'Added ✓' : 'Add'),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

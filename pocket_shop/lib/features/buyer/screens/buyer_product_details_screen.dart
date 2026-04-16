import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/product.dart';
import '../../../../providers/cart_provider.dart';
import '../../../../providers/review_provider.dart';
import '../../../../providers/wishlist_provider.dart';

class BuyerProductDetailsScreen extends ConsumerStatefulWidget {
  final Product product;

  const BuyerProductDetailsScreen({
    super.key,
    required this.product,
  });

  @override
  ConsumerState<BuyerProductDetailsScreen> createState() => _BuyerProductDetailsScreenState();
}

class _BuyerProductDetailsScreenState extends ConsumerState<BuyerProductDetailsScreen> {
  final PageController _imageController = PageController();
  int _activeImage = 0;
  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(reviewProvider.notifier).load(widget.product.id),
    );
  }

  @override
  void dispose() {
    _imageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final inStock = product.isAvailable && product.isInStock;
    final urls = product.imageUrls;
    final pageCount = urls.isEmpty ? 1 : urls.length;
    final wishlist = ref.watch(wishlistProvider);
    final wishlistNotifier = ref.read(wishlistProvider.notifier);
    final isFavorite = wishlist.contains(product.id);
    final reviewState = ref.watch(reviewProvider);
    final avgRating = reviewState.reviewCount > 0
        ? reviewState.averageRating
        : product.reviewAverage;
    final reviewCount = reviewState.reviewCount > 0
        ? reviewState.reviewCount
        : product.reviewCount;

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Product details'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            height: 260,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.divider),
              color: Colors.white,
            ),
            child: Stack(
              children: [
                PageView(
                  controller: _imageController,
                  onPageChanged: (index) {
                    setState(() {
                      _activeImage = index;
                    });
                  },
                  children: urls.isEmpty
                      ? [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              color: AppTheme.surfaceWhite,
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.photo_outlined,
                                    color: AppTheme.textSecondary.withValues(alpha: 0.9),
                                    size: 40,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'No photos for this listing',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textSecondary.withValues(alpha: 0.95),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'The seller has not added images yet. You can still read the description below.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.3,
                                      color: AppTheme.textSecondary.withValues(alpha: 0.85),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ]
                      : urls
                          .map(
                            (u) => ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.network(
                                u,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return Container(
                                    color: AppTheme.surfaceWhite,
                                    alignment: Alignment.center,
                                    child: SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppTheme.primaryCyan.withValues(alpha: 0.75),
                                      ),
                                    ),
                                  );
                                },
                                errorBuilder: (context, _, _) => Container(
                                  color: AppTheme.surfaceWhite,
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.broken_image_outlined,
                                        color: AppTheme.textSecondary,
                                        size: 36,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Image could not be loaded',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary.withValues(alpha: 0.9),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: InkWell(
                    onTap: () => wishlistNotifier.toggle(product.id),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: Icon(
                        isFavorite ? Icons.favorite : Icons.favorite_border,
                        size: 18,
                        color: isFavorite ? AppTheme.error : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 10,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(pageCount, (index) {
                      final selected = index == _activeImage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: selected ? 16 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: selected ? AppTheme.primaryCyan : AppTheme.divider,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      );
                    }),
                  ),
                ),
                if (urls.length > 1)
                  Positioned(
                    left: 10,
                    top: 10,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.view_carousel_outlined, size: 14, color: Colors.white),
                              const SizedBox(width: 6),
                              Text(
                                '${_activeImage + 1} / ${urls.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (urls.length > 1) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.touch_app_outlined,
                  size: 15,
                  color: AppTheme.textSecondary.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 6),
                Text(
                  'Swipe sideways to see all photos',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.divider),
              color: Colors.white,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.lightCyan.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      product.qualityDisplayLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.darkCyan,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, color: AppTheme.warning, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      avgRating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '($reviewCount)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      inStock ? 'In stock' : 'Out of stock',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: inStock ? AppTheme.darkCyan : AppTheme.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'ZMW ${product.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'by ${product.sellerName ?? 'Unknown seller'}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (product.variants.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: product.variants
                        .map(
                          (variant) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.lightCyan.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${variant.name}: ${variant.value} (${variant.stockQuantity})',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.darkCyan,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.divider),
              color: Colors.white,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Description',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  product.description.isEmpty
                      ? 'No description available for this product.'
                      : product.description,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text(
                      'Quantity',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    _QtyButton(
                      icon: Icons.remove,
                      onTap: _quantity > 1
                          ? () {
                              setState(() {
                                _quantity--;
                              });
                            }
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '$_quantity',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    _QtyButton(
                      icon: Icons.add,
                      onTap: inStock
                          ? () {
                              setState(() {
                                _quantity++;
                              });
                            }
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.divider),
              color: Colors.white,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Reviews',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => _openReviewSheet(context, product.id),
                      child: const Text('Write review'),
                    ),
                  ],
                ),
                if (reviewState.isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(color: AppTheme.primaryCyan),
                  )
                else if (reviewState.reviews.isEmpty)
                  const Text(
                    'No reviews yet.',
                    style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  )
                else
                  ...reviewState.reviews.take(3).map(
                    (review) => Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                review.authorName ?? 'Buyer',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${review.rating}/5',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              if (review.isVerifiedPurchase) ...[
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.verified_rounded,
                                  size: 14,
                                  color: AppTheme.success,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            review.comment.isEmpty
                                ? 'No comment provided.'
                                : review.comment,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 90),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: inStock
                    ? () async {
                        final cartNotifier = ref.read(cartProvider.notifier);
                        final err = await cartNotifier.addProduct(
                          product,
                          quantity: _quantity,
                        );
                        if (!context.mounted) return;
                        if (err != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(err),
                              backgroundColor: AppTheme.error,
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${product.name} added to cart'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        }
                      }
                    : null,
                child: const Text('Add to cart'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: inStock
                    ? () async {
                        final cartNotifier = ref.read(cartProvider.notifier);
                        final err = await cartNotifier.addProduct(
                          product,
                          quantity: _quantity,
                        );
                        if (!context.mounted) return;
                        if (err != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(err),
                              backgroundColor: AppTheme.error,
                            ),
                          );
                          return;
                        }
                        if (context.mounted) {
                          context.go('/buyer/cart');
                        }
                      }
                    : null,
                child: const Text('Buy now'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openReviewSheet(BuildContext context, int productId) async {
    int score = 5;
    final commentController = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Write a review',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              value: score,
              items: const [
                DropdownMenuItem(value: 5, child: Text('5 - Excellent')),
                DropdownMenuItem(value: 4, child: Text('4 - Good')),
                DropdownMenuItem(value: 3, child: Text('3 - Okay')),
                DropdownMenuItem(value: 2, child: Text('2 - Poor')),
                DropdownMenuItem(value: 1, child: Text('1 - Bad')),
              ],
              onChanged: (v) => score = v ?? 5,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: commentController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Share your experience',
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Submit'),
              ),
            ),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) return;
    final msg = await ref.read(reviewProvider.notifier).submit(
      productId: productId,
      rating: score,
      comment: commentController.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg ?? 'Review submitted'),
        backgroundColor: msg == null ? AppTheme.success : AppTheme.error,
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _QtyButton({
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.divider),
          color: Colors.white,
        ),
        child: Icon(
          icon,
          size: 16,
          color: onTap == null ? AppTheme.divider : AppTheme.textPrimary,
        ),
      ),
    );
  }
}

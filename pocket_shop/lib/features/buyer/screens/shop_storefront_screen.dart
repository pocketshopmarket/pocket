import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/product.dart';
import '../../../models/shop.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/wishlist_provider.dart';
import '../../../services/product_service.dart';
import '../../../services/shop_service.dart';
import '../../../widgets/product_list_thumbnail.dart';

/// A single seller's public storefront: header + their full in-stock catalog.
/// Reached from a `ShopCard` tap on Home (Near Me / All Shops) — the `Shop`
/// is usually passed via `extra`; `shopId` is a fallback for a direct link
/// (deep link, or a search result) that only has the id.
class ShopStorefrontScreen extends ConsumerStatefulWidget {
  const ShopStorefrontScreen({super.key, this.shop, this.shopId});

  final Shop? shop;
  final int? shopId;

  @override
  ConsumerState<ShopStorefrontScreen> createState() => _ShopStorefrontScreenState();
}

class _ShopStorefrontScreenState extends ConsumerState<ShopStorefrontScreen> {
  final ScrollController _scrollController = ScrollController();
  final ProductService _productService = ProductService();
  final ShopService _shopService = ShopService();

  Shop? _shop;
  bool _loadingShop = false;
  String? _shopError;

  List<Product> _items = [];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  int _nextPage = 1;
  bool _hasMore = true;

  int? get _sellerId => _shop?.id ?? widget.shopId;

  @override
  void initState() {
    super.initState();
    _shop = widget.shop;
    _scrollController.addListener(_onScroll);
    if (_shop == null && widget.shopId != null) {
      _loadShop();
    } else {
      _fetchProducts(reset: true);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadShop() async {
    setState(() => _loadingShop = true);
    try {
      final shop = await _shopService.getShop(widget.shopId!);
      if (!mounted) return;
      setState(() {
        _shop = shop;
        _loadingShop = false;
      });
      _fetchProducts(reset: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingShop = false;
        _shopError = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore || !_hasMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 180) {
      _fetchProducts(reset: false);
    }
  }

  Future<void> _fetchProducts({required bool reset}) async {
    final sellerId = _sellerId;
    if (sellerId == null) return;
    if (_loading || _loadingMore) return;
    if (!reset && !_hasMore) return;

    setState(() {
      if (reset) {
        _loading = true;
      } else {
        _loadingMore = true;
      }
      _error = null;
    });

    try {
      final currentPage = reset ? 1 : _nextPage;
      final page = await _productService.getProductsPage(
        ProductQuery(
          sellerId: sellerId,
          page: currentPage,
          inStockOnly: true,
          sortBy: 'latest',
        ),
      );
      if (!mounted) return;
      setState(() {
        _items = reset ? page.items : [..._items, ...page.items];
        _nextPage = page.nextPage ?? currentPage;
        _hasMore = page.nextPage != null;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wishlist = ref.watch(wishlistProvider);
    final wishlistNotifier = ref.read(wishlistProvider.notifier);
    final cartNotifier = ref.read(cartProvider.notifier);
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 360;

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: Text(_shop?.shopName ?? 'Shop'),
      ),
      body: _loadingShop
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryCyan))
          : _shopError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_shopError!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.error)),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _fetchProducts(reset: true),
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverToBoxAdapter(child: _buildHeader()),
                      if (_loading)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: CircularProgressIndicator(color: AppTheme.primaryCyan)),
                        )
                      else if (_error != null)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.error)),
                            ),
                          ),
                        )
                      else if (_items.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'This shop has no items in stock right now.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppTheme.textSecondary),
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
                          sliver: SliverGrid(
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: isCompact ? 8 : 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: isCompact ? 0.66 : 0.7,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                if (index >= _items.length) {
                                  return const Center(
                                    child: CircularProgressIndicator(color: AppTheme.primaryCyan),
                                  );
                                }
                                final product = _items[index];
                                return _StorefrontProductCard(
                                  product: product,
                                  isFavorite: wishlist.contains(product.id),
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
                              childCount: _items.length + (_loadingMore ? 1 : 0),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeader() {
    final shop = _shop;
    if (shop == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 64,
              height: 64,
              child: shop.shopLogo != null
                  ? CachedNetworkImage(
                      imageUrl: shop.shopLogo!,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => _headerFallbackIcon(),
                    )
                  : _headerFallbackIcon(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shop.shopName,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
                if (shop.shopDescription.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    shop.shopDescription,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.place_outlined, size: 12, color: AppTheme.textSecondary),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        shop.distanceKm != null
                            ? '${shop.shopLocation} · ${shop.distanceKm!.toStringAsFixed(1)} km away'
                            : shop.shopLocation,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerFallbackIcon() {
    return Container(
      color: AppTheme.divider.withValues(alpha: 0.3),
      alignment: Alignment.center,
      child: const Icon(Icons.storefront_outlined, size: 28, color: AppTheme.textSecondary),
    );
  }
}

class _StorefrontProductCard extends StatelessWidget {
  const _StorefrontProductCard({
    required this.product,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onCardTap,
    required this.onAdd,
  });

  final Product product;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onCardTap;
  final Future<void> Function() onAdd;

  @override
  Widget build(BuildContext context) {
    final inStock = product.isAvailable && product.isInStock;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
        boxShadow: const [
          BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: InkWell(
        onTap: onCardTap,
        borderRadius: BorderRadius.circular(12),
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
                      child: ProductListThumbnail(product: product, compactPlaceholder: true),
                    ),
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: InkWell(
                      onTap: onToggleFavorite,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.divider),
                        ),
                        child: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                          size: 16,
                          color: isFavorite ? AppTheme.error : AppTheme.textSecondary,
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
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              product.qualityDisplayLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'ZMW ${product.price.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                  ),
                ),
                InkWell(
                  onTap: inStock ? onAdd : null,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: Icon(
                      Icons.add_shopping_cart_rounded,
                      size: 16,
                      color: inStock ? AppTheme.darkCyan : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

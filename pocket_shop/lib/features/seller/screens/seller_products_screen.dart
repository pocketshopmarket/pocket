import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/product.dart';
import '../../../providers/product_provider.dart';
import '../../../services/product_service.dart';
import '../../../widgets/product_list_thumbnail.dart';

enum _StockFilter { all, inStock, lowStock, outOfStock }

class SellerProductsScreen extends ConsumerStatefulWidget {
  const SellerProductsScreen({super.key});

  @override
  ConsumerState<SellerProductsScreen> createState() =>
      _SellerProductsScreenState();
}

class _SellerProductsScreenState extends ConsumerState<SellerProductsScreen> {
  List<Product> _products = [];
  bool _loading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  _StockFilter _stockFilter = _StockFilter.all;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = ref.read(productServiceProvider);
      // The backend caps page_size at 50 regardless of what's requested
      // here, so a seller with more than one page of products (this is a
      // "manage my inventory" screen, not a browse feed) needs every page
      // fetched up front — otherwise search/stock-filter would silently
      // only cover whatever page happened to load first.
      final all = <Product>[];
      int page = 1;
      while (true) {
        final result = await svc.getProductsPage(ProductQuery(page: page, pageSize: 50));
        all.addAll(result.items);
        if (result.nextPage == null || result.items.isEmpty || page > 100) break;
        page = result.nextPage!;
      }
      if (mounted) setState(() => _products = all);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _matchesStockFilter(Product p) {
    switch (_stockFilter) {
      case _StockFilter.all:
        return true;
      case _StockFilter.outOfStock:
        return p.stockQuantity <= 0;
      case _StockFilter.lowStock:
        return p.stockQuantity > 0 && p.stockQuantity <= 5;
      case _StockFilter.inStock:
        return p.stockQuantity > 5;
    }
  }

  List<Product> get _filteredProducts {
    final query = _searchController.text.trim().toLowerCase();
    return _products.where((p) {
      if (!_matchesStockFilter(p)) return false;
      if (query.isEmpty) return true;
      return p.name.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _delete(Product product) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text(
          '"${product.name}" will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(productServiceProvider).deleteProduct(product.id);
      setState(() => _products.removeWhere((p) => p.id == product.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product deleted'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Widget _filterChip(String label, _StockFilter value) {
    final selected = _stockFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _stockFilter = value),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : AppTheme.textPrimary,
        ),
        selectedColor: AppTheme.primaryCyan,
        backgroundColor: Colors.white,
        side: const BorderSide(color: AppTheme.divider),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProducts;
    final hasBaseProducts = _products.isNotEmpty;

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('My products'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/seller/products/add').then((_) => _load()),
        icon: const Icon(Icons.add),
        label: const Text('Add product'),
        backgroundColor: AppTheme.primaryCyan,
        foregroundColor: Colors.black,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryCyan),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _products.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.storefront_outlined,
                            size: 56,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No products yet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Tap + Add product to list your first item.',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEEEEE),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.search_rounded, color: AppTheme.textSecondary, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    style: const TextStyle(fontSize: 14),
                                    decoration: InputDecoration(
                                      hintText: 'Search my products',
                                      hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                      suffixIcon: _searchController.text.isNotEmpty
                                          ? GestureDetector(
                                              onTap: () => _searchController.clear(),
                                              child: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textSecondary),
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: SizedBox(
                            height: 32,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                _filterChip('All (${_products.length})', _StockFilter.all),
                                _filterChip(
                                  'In stock (${_products.where((p) => p.stockQuantity > 5).length})',
                                  _StockFilter.inStock,
                                ),
                                _filterChip(
                                  'Low stock (${_products.where((p) => p.stockQuantity > 0 && p.stockQuantity <= 5).length})',
                                  _StockFilter.lowStock,
                                ),
                                _filterChip(
                                  'Out of stock (${_products.where((p) => p.stockQuantity <= 0).length})',
                                  _StockFilter.outOfStock,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: filtered.isEmpty && hasBaseProducts
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      _searchController.text.trim().isNotEmpty
                                          ? 'No products match "${_searchController.text.trim()}".'
                                          : 'No products match this filter.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: AppTheme.textSecondary),
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                                  itemCount: filtered.length,
                                  itemBuilder: (_, i) => _ProductTile(
                                    product: filtered[i],
                                    onDelete: () => _delete(filtered[i]),
                                  ),
                                ),
                        ),
                      ],
                    ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onDelete;

  const _ProductTile({required this.product, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final stockColor = product.stockQuantity <= 0
        ? AppTheme.error
        : product.stockQuantity <= 5
            ? AppTheme.warning
            : AppTheme.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.go('/seller/products/${product.id}/edit'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 68,
                  height: 68,
                  child: ProductListThumbnail(product: product, compactPlaceholder: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ZMW ${product.price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppTheme.darkCyan,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: stockColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            product.stockQuantity <= 0
                                ? 'Out of stock'
                                : product.stockQuantity <= 5
                                    ? 'Low stock · ${product.stockQuantity}'
                                    : 'Stock: ${product.stockQuantity}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: stockColor,
                            ),
                          ),
                        ),
                        if (product.reviewCount > 0) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.star_rounded,
                            size: 13,
                            color: AppTheme.warning,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${product.reviewAverage.toStringAsFixed(1)} (${product.reviewCount})',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.edit_outlined,
                      color: AppTheme.darkCyan,
                      size: 20,
                    ),
                    tooltip: 'Edit',
                    onPressed: () =>
                        context.go('/seller/products/${product.id}/edit'),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: AppTheme.error,
                      size: 20,
                    ),
                    tooltip: 'Delete',
                    onPressed: onDelete,
                  ),
                  if (product.reviewCount > 0)
                    IconButton(
                      icon: const Icon(
                        Icons.rate_review_outlined,
                        color: AppTheme.textSecondary,
                        size: 20,
                      ),
                      tooltip: 'Reviews',
                      onPressed: () => context.go(
                        '/seller/products/${product.id}/reviews',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

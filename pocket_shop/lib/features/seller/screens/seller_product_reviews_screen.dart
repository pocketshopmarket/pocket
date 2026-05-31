import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/api_service.dart';

class SellerProductReviewsScreen extends ConsumerStatefulWidget {
  final int productId;
  final String productName;

  const SellerProductReviewsScreen({
    super.key,
    required this.productId,
    required this.productName,
  });

  @override
  ConsumerState<SellerProductReviewsScreen> createState() =>
      _SellerProductReviewsScreenState();
}

class _SellerProductReviewsScreenState
    extends ConsumerState<SellerProductReviewsScreen> {
  List<Map<String, dynamic>> _reviews = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ApiService();
      final response = await api.get(
        '${AppConstants.sellerProductReviewsPrefix}${widget.productId}/',
      );
      final raw = response.data;
      final list = raw is List
          ? raw
          : (raw is Map && raw['results'] is List)
              ? raw['results'] as List
              : <dynamic>[];
      if (mounted) {
        setState(() => _reviews = list.cast<Map<String, dynamic>>());
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: Text('Reviews — ${widget.productName}'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryCyan))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.textSecondary)))
              : _reviews.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.rate_review_outlined, size: 48, color: AppTheme.textSecondary),
                          SizedBox(height: 12),
                          Text('No reviews yet', style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
                        ],
                      ),
                    )
                  : _buildSummary(),
    );
  }

  Widget _buildSummary() {
    final total = _reviews.length;
    final avg = _reviews.isEmpty
        ? 0.0
        : _reviews.map((r) => (r['rating'] as num?)?.toDouble() ?? 0).reduce((a, b) => a + b) / total;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              Column(
                children: [
                  Text(
                    avg.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: AppTheme.textPrimary),
                  ),
                  Row(
                    children: List.generate(5, (i) => Icon(
                      i < avg.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 18,
                      color: AppTheme.warning,
                    )),
                  ),
                  const SizedBox(height: 4),
                  Text('$total review${total == 1 ? '' : 's'}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: List.generate(5, (i) {
                    final star = 5 - i;
                    final count = _reviews.where((r) => (r['rating'] as num?)?.round() == star).length;
                    final fraction = total > 0 ? count / total : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Text('$star', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                          const SizedBox(width: 4),
                          Icon(Icons.star_rounded, size: 12, color: AppTheme.warning),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: fraction,
                                backgroundColor: AppTheme.divider,
                                color: AppTheme.warning,
                                minHeight: 6,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text('$count', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ..._reviews.map((r) => _ReviewCard(review: r)),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final author = review['author_name']?.toString() ?? 'Buyer';
    final comment = review['comment']?.toString() ?? '';
    final verified = review['is_verified_purchase'] == true;
    final date = review['created_at']?.toString().substring(0, 10) ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Row(
                children: List.generate(5, (i) => Icon(
                  i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 15, color: AppTheme.warning,
                )),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  author,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (verified)
                const Icon(Icons.verified_rounded, size: 14, color: AppTheme.success),
              const SizedBox(width: 4),
              Text(date, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(comment, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

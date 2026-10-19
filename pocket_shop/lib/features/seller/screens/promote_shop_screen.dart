import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/seller_banner.dart';
import '../../../providers/platform_settings_provider.dart';
import '../../../services/banner_service.dart';

final _myBannersProvider = FutureProvider.autoDispose<List<SellerBanner>>((ref) {
  return BannerService().myBanners();
});

class PromoteShopScreen extends ConsumerWidget {
  const PromoteShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(bannerSlotEnabledProvider);
    final pricePerDay = ref.watch(bannerSlotPricePerDayProvider);
    final banners = ref.watch(_myBannersProvider);

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('Promote your shop'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(_myBannersProvider),
          ),
        ],
      ),
      floatingActionButton: enabled
          ? FloatingActionButton.extended(
              onPressed: () => _openRequestSheet(context, ref, pricePerDay),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New promotion'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_myBannersProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primaryCyan.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.primaryCyan),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      enabled
                          ? 'Get a "Sponsored" banner on the buyer home screen for a flat '
                              'ZMW ${pricePerDay.toStringAsFixed(0)} per day. Every request is '
                              'checked by our team before it goes live.'
                          : 'Shop promotion is not available right now. Please check back later.',
                      style: const TextStyle(fontSize: 13, height: 1.4, color: AppTheme.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Your requests',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 10),
            banners.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  BannerService.errorMessage(e, fallback: 'Could not load your promotions.'),
                  style: const TextStyle(color: AppTheme.error),
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No promotions yet',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                  );
                }
                return Column(
                  children: items.map((b) => _BannerHistoryCard(banner: b)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRequestSheet(BuildContext context, WidgetRef ref, double pricePerDay) async {
    final created = await showModalBottomSheet<SellerBanner>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _RequestBannerSheet(pricePerDay: pricePerDay),
    );
    if (created != null && context.mounted) {
      ref.invalidate(_myBannersProvider);
      context.push('/seller/promote-shop/pay', extra: created);
    }
  }
}

class _BannerHistoryCard extends StatelessWidget {
  final SellerBanner banner;
  const _BannerHistoryCard({required this.banner});

  Color _statusColor() {
    switch (banner.status) {
      case 'active':
        return AppTheme.success;
      case 'rejected':
      case 'expired':
        return AppTheme.error;
      case 'pending_payment':
        return AppTheme.warning;
      default:
        return AppTheme.primaryCyan;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  banner.title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  banner.statusLabel,
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'ZMW ${banner.pricePaid} · ${banner.durationDays} day(s)',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          if (banner.status == 'pending_payment') ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton(
                onPressed: () => context.push('/seller/promote-shop/pay', extra: banner),
                child: const Text('Finish payment'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RequestBannerSheet extends ConsumerStatefulWidget {
  final double pricePerDay;
  const _RequestBannerSheet({required this.pricePerDay});

  @override
  ConsumerState<_RequestBannerSheet> createState() => _RequestBannerSheetState();
}

class _RequestBannerSheetState extends ConsumerState<_RequestBannerSheet> {
  final _titleController = TextEditingController();
  final _subtitleController = TextEditingController();
  int _durationDays = 7;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give your promotion a title.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final banner = await BannerService().requestBanner(
        title: title,
        subtitle: _subtitleController.text.trim(),
        durationDays: _durationDays,
      );
      if (mounted) Navigator.pop(context, banner);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = BannerService.errorMessage(e, fallback: 'Could not submit this request.');
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = (widget.pricePerDay * _durationDays);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'New promotion',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. Fresh produce, daily deliveries',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _subtitleController,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Subtitle (optional)',
                hintText: 'e.g. Order before 10am for same-day delivery',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Duration',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: _durationDays > 1 ? () => setState(() => _durationDays--) : null,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                ),
                Expanded(
                  child: Slider(
                    value: _durationDays.toDouble(),
                    min: 1,
                    max: 90,
                    divisions: 89,
                    label: '$_durationDays day(s)',
                    onChanged: (v) => setState(() => _durationDays = v.round()),
                  ),
                ),
                IconButton(
                  onPressed: _durationDays < 90 ? () => setState(() => _durationDays++) : null,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              ],
            ),
            Text(
              '$_durationDays day(s)',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primaryCyan.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    'ZMW ${price.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.primaryCyan),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Continue to payment'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

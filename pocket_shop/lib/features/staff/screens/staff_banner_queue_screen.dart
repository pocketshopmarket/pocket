import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/staff_service.dart';
import '../widgets/staff_widgets.dart';

final _bannerQueueProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return StaffService().getBannerQueue();
});

class StaffBannerQueueScreen extends ConsumerWidget {
  const StaffBannerQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_bannerQueueProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Banner reviews'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(_bannerQueueProvider),
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => StaffRetryCenter(
          message: StaffService.errorMessage(e, fallback: 'Could not load the banner queue. Check your connection.'),
          onRetry: () => ref.invalidate(_bannerQueueProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const StaffEmptyCenter(label: 'No banners awaiting review');
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_bannerQueueProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, i) => _BannerCard(
                item: items[i],
                onAction: () => ref.invalidate(_bannerQueueProvider),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BannerCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onAction;

  const _BannerCard({required this.item, required this.onAction});

  @override
  State<_BannerCard> createState() => _BannerCardState();
}

class _BannerCardState extends State<_BannerCard> {
  bool _loading = false;

  Future<void> _approve() async {
    final confirm = await askStaffConfirm(
      context,
      title: 'Approve banner?',
      message: '"${widget.item['title']}" will go live on the home screen for '
          '${widget.item['duration_days']} day(s).',
      confirmLabel: 'Approve',
    );
    if (!confirm) return;
    setState(() => _loading = true);
    try {
      await StaffService().approveBanner(widget.item['id'] as int);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Approved — now live'), backgroundColor: Colors.green),
        );
        widget.onAction();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(StaffService.errorMessage(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _RejectReasonDialog(title: '${widget.item['title']}'),
    );
    if (reason == null) return;
    setState(() => _loading = true);
    try {
      await StaffService().rejectBanner(widget.item['id'] as int, reason: reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rejected'), backgroundColor: Colors.orange),
        );
        widget.onAction();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(StaffService.errorMessage(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final imageUrl = item['image_url'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item['title'] as String? ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                StaffBadge(
                  label: 'ZMW ${item['price_paid']}',
                  background: Colors.green.shade100,
                  foreground: Colors.green.shade800,
                ),
              ],
            ),
            if ((item['subtitle'] as String? ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(item['subtitle'] as String, style: const TextStyle(fontSize: 13, color: Colors.black54)),
            ],
            const SizedBox(height: 8),
            if (imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  height: 110,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              )
            else
              Container(
                height: 70,
                decoration: BoxDecoration(
                  color: Color(int.tryParse(
                            (item['bg_color'] as String? ?? '#F97316').replaceFirst('#', '0xFF'),
                          ) ??
                          0xFFF97316),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            const SizedBox(height: 8),
            StaffInfoRow(label: 'Seller', value: item['seller_name'] as String? ?? ''),
            StaffInfoRow(label: 'Phone', value: item['seller_phone'] as String? ?? ''),
            StaffInfoRow(label: 'Duration', value: '${item['duration_days']} day(s)'),
            if ((item['created_at'] as String? ?? '').isNotEmpty)
              StaffInfoRow(
                label: 'Requested',
                value: (item['created_at'] as String).split('T').first,
              ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _reject,
                      icon: const Icon(Icons.close, color: Colors.red),
                      label: const Text('Reject', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _approve,
                      icon: const Icon(Icons.check),
                      label: const Text('Approve'),
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

/// Asks why a banner is being rejected. The seller reads this, so it's required.
class _RejectReasonDialog extends StatefulWidget {
  final String title;
  const _RejectReasonDialog({required this.title});

  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _reason.text.trim().length >= 3;
    return AlertDialog(
      title: const Text('Reject banner'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reject "${widget.title}"? The seller will see your reason.'),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            autofocus: true,
            maxLines: 2,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Reason (required)',
              hintText: 'e.g. Image is low quality, please re-upload',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: valid ? () => Navigator.pop(context, _reason.text.trim()) : null,
          child: const Text('Reject'),
        ),
      ],
    );
  }
}

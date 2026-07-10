import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/staff_service.dart';

final _refundsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return StaffService().getRefunds();
});

class StaffRefundsScreen extends ConsumerWidget {
  const StaffRefundsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_refundsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cancellations & Refunds'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(_refundsProvider),
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 8),
              const Text('Could not load refunds. Check your connection.'),
              TextButton(
                onPressed: () => ref.invalidate(_refundsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline, size: 56, color: Colors.green),
                  SizedBox(height: 8),
                  Text('No cancelled orders'),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_refundsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, i) => _RefundCard(
                item: items[i],
                onRefunded: () => ref.invalidate(_refundsProvider),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RefundCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onRefunded;

  const _RefundCard({required this.item, required this.onRefunded});

  @override
  State<_RefundCard> createState() => _RefundCardState();
}

class _RefundCardState extends State<_RefundCard> {
  bool _loading = false;
  String? _proofImagePath;

  Future<void> _markRefunded(Map<String, dynamic> pendingRefund) async {
    final txId = pendingRefund['transaction_id'] as String;
    final amount = pendingRefund['amount']?.toString() ?? '';
    final phone = pendingRefund['refund_phone'] as String? ?? '';
    final notesController = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Confirm Refund Sent?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Confirm you sent ZMW $amount back to '
                '${widget.item['buyer_name']} ($phone)',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Reference / Notes (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await ImagePicker()
                      .pickImage(source: ImageSource.gallery, imageQuality: 85);
                  if (picked != null) setLocal(() => _proofImagePath = picked.path);
                },
                icon: const Icon(Icons.attach_file_rounded, size: 18),
                label: Text(_proofImagePath != null
                    ? 'Receipt attached ✓'
                    : 'Attach MoMo screenshot'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      await StaffService().markRefunded(
        txId,
        notes: notesController.text,
        proofImagePath: _proofImagePath,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Marked as refunded'), backgroundColor: Colors.green),
        );
        widget.onRefunded();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not mark as refunded. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copyPhone(String phone) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copied $phone'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final wasPaid = item['was_paid'] as bool? ?? false;
    final refundCount = item['refund_count'] as int? ?? 0;
    final refundStatuses = item['refund_statuses'] as List? ?? [];
    final pendingRefund = item['pending_refund'] as Map<String, dynamic>?;
    final refundCompleted = item['refund_completed'] as bool? ?? false;
    final proofUrl = item['refund_proof_url'] as String?;
    final hasPendingRefund = pendingRefund != null;

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
                    '#${item['order_number']}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                _StatusBadge(
                  wasPaid: wasPaid,
                  hasPendingRefund: hasPendingRefund,
                  refundCompleted: refundCompleted,
                ),
              ],
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _copyPhone(item['buyer_phone'] as String? ?? ''),
              child: _InfoRow(
                label: 'Buyer',
                value: '${item['buyer_name']} (${item['buyer_phone']})',
              ),
            ),
            _InfoRow(label: 'Seller', value: item['seller_name'] as String? ?? ''),
            _InfoRow(label: 'Total', value: 'ZMW ${item['grand_total']}'),
            if (refundCount > 0)
              _InfoRow(label: 'Refunds', value: '$refundCount (${refundStatuses.join(", ")})'),
            if ((item['cancelled_at'] as String? ?? '').isNotEmpty)
              _InfoRow(
                label: 'Cancelled',
                value: (item['cancelled_at'] as String).split('T').first,
              ),
            if (proofUrl != null) ...[
              const SizedBox(height: 8),
              _ProofThumbnail(url: proofUrl),
            ],
            if (hasPendingRefund) ...[
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Send ZMW ${pendingRefund['amount']} back to '
                        '${pendingRefund['refund_phone']} (tap buyer row to copy), '
                        'then mark it refunded below.',
                        style: TextStyle(color: Colors.red.shade700, fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading ? null : () => _markRefunded(pendingRefund),
                  icon: _loading
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.assignment_return_rounded),
                  label: const Text('Mark Refunded'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool wasPaid;
  final bool hasPendingRefund;
  final bool refundCompleted;

  const _StatusBadge({
    required this.wasPaid,
    required this.hasPendingRefund,
    required this.refundCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color bg;
    final Color fg;
    if (!wasPaid) {
      label = 'Not Paid';
      bg = Colors.grey.shade200;
      fg = Colors.grey.shade700;
    } else if (refundCompleted && !hasPendingRefund) {
      label = 'Refunded';
      bg = Colors.green.shade100;
      fg = Colors.green.shade800;
    } else if (hasPendingRefund) {
      label = 'Refund Pending';
      bg = Colors.red.shade100;
      fg = Colors.red.shade800;
    } else {
      label = 'Paid';
      bg = Colors.grey.shade200;
      fg = Colors.grey.shade700;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(color: fg, fontSize: 12)),
    );
  }
}

class _ProofThumbnail extends StatelessWidget {
  final String url;
  const _ProofThumbnail({required this.url});

  void _viewFull(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('Refund Receipt'),
          ),
          body: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _viewFull(context),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: url,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              placeholder: (_, __) => const SizedBox(
                  width: 64, height: 64,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              errorWidget: (_, __, ___) => const SizedBox(
                  width: 64, height: 64, child: Icon(Icons.broken_image_outlined)),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Refund receipt attached — tap to view',
            style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

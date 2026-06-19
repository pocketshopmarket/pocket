import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
              Text(e.toString()),
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
              itemBuilder: (context, i) => _RefundCard(item: items[i]),
            ),
          );
        },
      ),
    );
  }
}

class _RefundCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const _RefundCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final wasPaid = item['was_paid'] as bool? ?? false;
    final refundCount = item['refund_count'] as int? ?? 0;
    final refundStatuses = item['refund_statuses'] as List? ?? [];
    final hasPendingRefund = refundStatuses.contains('pending');

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
                if (wasPaid)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: hasPendingRefund ? Colors.red.shade100 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      hasPendingRefund ? 'Refund Pending' : 'Paid',
                      style: TextStyle(
                        color: hasPendingRefund ? Colors.red.shade800 : Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Not Paid',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _InfoRow(label: 'Buyer', value: '${item['buyer_name']} (${item['buyer_phone']})'),
            _InfoRow(label: 'Seller', value: item['seller_name'] as String? ?? ''),
            _InfoRow(label: 'Total', value: 'ZMW ${item['grand_total']}'),
            if (refundCount > 0)
              _InfoRow(label: 'Refunds', value: '$refundCount (${refundStatuses.join(", ")})'),
            if ((item['cancelled_at'] as String? ?? '').isNotEmpty)
              _InfoRow(
                label: 'Cancelled',
                value: (item['cancelled_at'] as String).split('T').first,
              ),
            if (wasPaid && hasPendingRefund)
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
                        'This order was paid — a refund may need to be processed manually.',
                        style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
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

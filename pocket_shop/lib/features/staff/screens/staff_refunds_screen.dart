import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/staff_service.dart';
import '../widgets/staff_widgets.dart';

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
        title: const Text('Refunds'),
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
        error: (e, _) => StaffRetryCenter(
          message: StaffService.errorMessage(e, fallback: 'Could not load refunds. Check your connection.'),
          onRetry: () => ref.invalidate(_refundsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const StaffEmptyCenter(label: 'No refunds to handle');
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_refundsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, i) => _RefundCard(
                item: items[i],
                onChanged: () => ref.invalidate(_refundsProvider),
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
  final VoidCallback onChanged;

  const _RefundCard({required this.item, required this.onChanged});

  @override
  State<_RefundCard> createState() => _RefundCardState();
}

class _RefundCardState extends State<_RefundCard> {
  bool _loading = false;

  void _snack(String message, {required bool ok}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: ok ? Colors.green : Colors.red),
    );
  }

  Future<void> _markRefunded(Map<String, dynamic> pending) async {
    final proof = await askManualSendProof(
      context,
      title: 'Confirm refund sent?',
      message: 'Confirm you sent ZMW ${pending['amount']} to '
          '${widget.item['buyer_name']} (${pending['refund_phone']}).',
    );
    if (proof == null) return;

    setState(() => _loading = true);
    try {
      await StaffService().markRefunded(
        pending['transaction_id'] as String,
        notes: proof.notes,
        proofImagePath: proof.proofImagePath,
      );
      _snack('Marked as refunded', ok: true);
      widget.onChanged();
    } catch (e) {
      _snack(StaffService.errorMessage(e, fallback: 'Could not mark as refunded. Please try again.'), ok: false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendViaLenco(Map<String, dynamic> pending) async {
    final ok = await askStaffConfirm(
      context,
      title: 'Send refund via Lenco?',
      message: 'Send ZMW ${pending['amount']} from the Lenco account to '
          '${pending['refund_phone']} (${widget.item['buyer_name']}). '
          'This cannot be undone.',
      confirmLabel: 'Send refund',
    );
    if (!ok) return;

    setState(() => _loading = true);
    try {
      final result = await StaffService().sendViaLenco(pending['transaction_id'] as String);
      _snack(result['message']?.toString() ?? 'Refund sent.', ok: true);
      widget.onChanged();
    } catch (e) {
      _snack(StaffService.errorMessage(e, fallback: 'Could not send the refund. Please try again.'), ok: false);
      widget.onChanged(); // the server records why it was refused
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final wasPaid = item['was_paid'] as bool? ?? false;
    final refundCount = item['refund_count'] as int? ?? 0;
    final refundStatuses = item['refund_statuses'] as List? ?? [];
    final pending = item['pending_refund'] as Map<String, dynamic>?;
    final inFlight = item['refund_in_flight'] as bool? ?? false;
    final refundCompleted = item['refund_completed'] as bool? ?? false;
    final proofUrl = item['refund_proof_url'] as String?;
    final orderStatus = item['order_status'] as String? ?? '';
    final updated = (item['cancelled_at'] as String? ?? '').split('T').first;

    final due = staffDueLabel(pending?['due_at'] as String?);
    final isCard = pending?['is_card_refund'] == true;
    final canSendViaLenco = pending?['can_send_via_lenco'] == true;
    final lastFailure = (pending?['failure_message'] as String? ?? '').trim();
    final note = (pending?['notes'] as String? ?? '').trim();

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
                _statusBadge(
                  wasPaid: wasPaid,
                  hasPending: pending != null,
                  inFlight: inFlight,
                  refundCompleted: refundCompleted,
                ),
              ],
            ),
            const SizedBox(height: 8),
            StaffInfoRow(
              label: 'Buyer',
              value: '${item['buyer_name']} (${item['buyer_phone']})',
            ),
            StaffInfoRow(label: 'Seller', value: item['seller_name'] as String? ?? ''),
            StaffInfoRow(label: 'Order total', value: 'ZMW ${item['grand_total']}'),
            if (refundCount > 0)
              StaffInfoRow(label: 'Refunds', value: '$refundCount (${refundStatuses.join(", ")})'),
            if (updated.isNotEmpty)
              StaffInfoRow(
                // The date is when the order last changed; only call it a
                // cancellation if the order really was cancelled.
                label: orderStatus == 'cancelled' ? 'Cancelled' : 'Updated',
                value: updated,
              ),
            if (proofUrl != null) ...[
              const SizedBox(height: 8),
              StaffProofThumbnail(url: proofUrl, title: 'Refund receipt'),
            ],
            if (pending != null) ...[
              const SizedBox(height: 4),
              // The number to pay is the REFUND number, which for a card
              // payment is not necessarily the buyer's own phone.
              StaffInfoRow(
                label: 'Refund to',
                value: pending['refund_phone'] as String? ?? '',
                copyable: true,
              ),
              if (due.label.isNotEmpty)
                StaffInfoRow(
                  label: 'Due by',
                  value: due.overdue ? '${due.label}  (OVERDUE)' : due.label,
                ),
              if (isCard)
                const StaffCallout(
                  text: 'Card payment — it cannot go back to the card. Pay the mobile money number above.',
                  color: Colors.blue,
                  icon: Icons.credit_card_rounded,
                ),
              if (note.isNotEmpty && !isCard) StaffCallout(text: note, color: Colors.orange, icon: Icons.info_outline),
              if (isCard && note.contains('NO valid'))
                StaffCallout(text: note, color: Colors.red),
              if (lastFailure.isNotEmpty)
                StaffCallout(text: 'Last attempt failed: $lastFailure', color: Colors.red),
              if (due.overdue)
                const StaffCallout(text: 'This refund is past the date promised to the buyer.', color: Colors.red),
              const SizedBox(height: 12),
              if (canSendViaLenco)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : () => _sendViaLenco(pending),
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded),
                    label: const Text('Send via Lenco'),
                  ),
                ),
              if (canSendViaLenco) const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: canSendViaLenco
                    ? OutlinedButton.icon(
                        onPressed: _loading ? null : () => _markRefunded(pending),
                        icon: const Icon(Icons.assignment_return_rounded),
                        label: const Text('Mark refunded (paid by hand)'),
                      )
                    : FilledButton.icon(
                        onPressed: _loading ? null : () => _markRefunded(pending),
                        icon: const Icon(Icons.assignment_return_rounded),
                        label: const Text('Mark Refunded'),
                      ),
              ),
            ] else if (inFlight)
              const StaffCallout(
                text: 'Refund sent through Lenco — waiting for confirmation. It turns to Refunded on its own.',
                color: Colors.blue,
                icon: Icons.hourglass_top_rounded,
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge({
    required bool wasPaid,
    required bool hasPending,
    required bool inFlight,
    required bool refundCompleted,
  }) {
    if (!wasPaid) {
      return StaffBadge(label: 'Not paid', background: Colors.grey.shade200, foreground: Colors.grey.shade700);
    }
    if (hasPending) {
      return StaffBadge(label: 'Refund pending', background: Colors.red.shade100, foreground: Colors.red.shade800);
    }
    // Previously an in-flight refund fell through to "Paid", which read as
    // though nothing was owed.
    if (inFlight) {
      return StaffBadge(label: 'Sending refund', background: Colors.blue.shade100, foreground: Colors.blue.shade800);
    }
    if (refundCompleted) {
      return StaffBadge(label: 'Refunded', background: Colors.green.shade100, foreground: Colors.green.shade800);
    }
    return StaffBadge(label: 'Paid', background: Colors.grey.shade200, foreground: Colors.grey.shade700);
  }
}

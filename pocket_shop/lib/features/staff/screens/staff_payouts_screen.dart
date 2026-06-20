import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/staff_service.dart';

final _sellerQueueProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return StaffService().getPayoutQueue(role: 'seller');
});

final _riderQueueProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return StaffService().getPayoutQueue(role: 'delivery');
});

final _earningsClaimsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return StaffService().getWithdrawals();
});

class StaffPayoutsScreen extends ConsumerStatefulWidget {
  const StaffPayoutsScreen({super.key});

  @override
  ConsumerState<StaffPayoutsScreen> createState() => _StaffPayoutsScreenState();
}

class _StaffPayoutsScreenState extends ConsumerState<StaffPayoutsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payouts'),
        centerTitle: false,
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Sellers'),
            Tab(text: 'Riders'),
            Tab(text: 'Earnings Claims'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(_sellerQueueProvider);
              ref.invalidate(_riderQueueProvider);
              ref.invalidate(_earningsClaimsProvider);
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _PayoutList(
            providerListen: _sellerQueueProvider,
            roleLabel: 'Seller',
          ),
          _PayoutList(
            providerListen: _riderQueueProvider,
            roleLabel: 'Rider',
          ),
          _EarningsClaimsList(providerListen: _earningsClaimsProvider),
        ],
      ),
    );
  }
}

// ── Payout queue tab ──────────────────────────────────────────────────────

class _PayoutList extends ConsumerWidget {
  final AutoDisposeFutureProvider<List<Map<String, dynamic>>> providerListen;
  final String roleLabel;

  const _PayoutList({required this.providerListen, required this.roleLabel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(providerListen);
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _RetryCenter(message: e.toString(), onRetry: () => ref.invalidate(providerListen)),
      data: (items) {
        if (items.isEmpty) {
          return _EmptyCenter(label: 'No pending $roleLabel payouts');
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(providerListen),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, i) => _PayoutCard(
              item: items[i],
              onPaid: () => ref.invalidate(providerListen),
            ),
          ),
        );
      },
    );
  }
}

class _PayoutCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onPaid;

  const _PayoutCard({required this.item, required this.onPaid});

  @override
  State<_PayoutCard> createState() => _PayoutCardState();
}

class _PayoutCardState extends State<_PayoutCard> {
  bool _loading = false;
  String? _proofImagePath;

  Future<void> _markPaid() async {
    final notesController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Mark as Paid?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Confirm you sent ZMW ${widget.item['amount']} to '
                '${widget.item['recipient_name']} (${widget.item['recipient_phone']})',
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
                  final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
                  if (picked != null) setLocal(() => _proofImagePath = picked.path);
                },
                icon: const Icon(Icons.attach_file_rounded, size: 18),
                label: Text(_proofImagePath != null ? 'Receipt attached ✓' : 'Attach MoMo screenshot'),
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
      await StaffService().markPaid(
        widget.item['transaction_id'] as String,
        notes: notesController.text,
        proofImagePath: _proofImagePath,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Marked as paid'), backgroundColor: Colors.green),
        );
        widget.onPaid();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final triggerLabel = _triggerLabel(item['trigger_event'] as String? ?? '');
    final proofUrl = item['proof_image_url'] as String?;

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
                    item['recipient_name'] as String? ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                _TriggerBadge(label: triggerLabel),
                const SizedBox(width: 8),
                _AmountBadge(amount: 'ZMW ${item['amount']}'),
              ],
            ),
            const SizedBox(height: 8),
            _CopyPhoneRow(phone: item['recipient_phone'] as String? ?? ''),
            _InfoRow(label: 'Order', value: '#${item['order_number']}'),
            _InfoRow(label: 'Network', value: item['provider'] as String? ?? ''),
            if ((item['payout_notes'] as String? ?? '').isNotEmpty)
              _InfoRow(label: 'Notes', value: item['payout_notes'] as String),
            if (proofUrl != null) ...[
              const SizedBox(height: 8),
              _ProofThumbnail(url: proofUrl),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _markPaid,
                icon: _loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_outline),
                label: const Text('Mark Paid'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Withdrawals tab ───────────────────────────────────────────────────────

class _EarningsClaimsList extends ConsumerWidget {
  final AutoDisposeFutureProvider<List<Map<String, dynamic>>> providerListen;

  const _EarningsClaimsList({required this.providerListen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(providerListen);
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _RetryCenter(message: e.toString(), onRetry: () => ref.invalidate(providerListen)),
      data: (items) {
        if (items.isEmpty) {
          return const _EmptyCenter(label: 'No pending earnings claims');
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(providerListen),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, i) => _EarningsClaimsCard(
              item: items[i],
              onPaid: () => ref.invalidate(providerListen),
            ),
          ),
        );
      },
    );
  }
}

class _EarningsClaimsCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onPaid;

  const _EarningsClaimsCard({required this.item, required this.onPaid});

  @override
  State<_EarningsClaimsCard> createState() => _EarningsClaimsCardState();
}

class _EarningsClaimsCardState extends State<_EarningsClaimsCard> {
  bool _loading = false;
  String? _proofImagePath;

  Future<void> _markPaid() async {
    final notesController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Confirm Earnings Paid?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Confirm you sent ZMW ${widget.item['amount']} to '
                '${widget.item['recipient_name']} (${widget.item['recipient_phone']})',
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
                  final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
                  if (picked != null) setLocal(() => _proofImagePath = picked.path);
                },
                icon: const Icon(Icons.attach_file_rounded, size: 18),
                label: Text(_proofImagePath != null ? 'Receipt attached ✓' : 'Attach MoMo screenshot'),
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
      await StaffService().markPaid(
        widget.item['transaction_id'] as String,
        notes: notesController.text,
        proofImagePath: _proofImagePath,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Marked as paid'), backgroundColor: Colors.green),
        );
        widget.onPaid();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final role = item['recipient_role'] as String? ?? '';
    final roleColor = role == 'seller' ? Colors.indigo : Colors.teal;

    final queuePaid = double.tryParse(item['queue_already_paid']?.toString() ?? '0') ?? 0.0;
    final availableBalance = double.tryParse(item['available_balance']?.toString() ?? '0') ?? 0.0;
    final totalEarned = double.tryParse(item['total_earned']?.toString() ?? '0') ?? 0.0;
    final claimAmount = double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
    final proofUrl = item['proof_image_url'] as String?;

    // overpay: paying this claim would exceed what's actually available
    final isOverpay = availableBalance < 0;
    // caution: some earnings already paid from queue but balance is still ok
    final hasQueuePayment = queuePaid > 0 && !isOverpay;

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
                    item['recipient_name'] as String? ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: roleColor.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    role == 'seller' ? 'Seller' : 'Rider',
                    style: TextStyle(color: roleColor.shade800, fontSize: 12),
                  ),
                ),
                _AmountBadge(amount: 'ZMW ${item['amount']}'),
              ],
            ),
            const SizedBox(height: 8),
            _CopyPhoneRow(phone: item['recipient_phone'] as String? ?? ''),
            _InfoRow(label: 'Network', value: item['provider'] as String? ?? ''),
            _InfoRow(label: 'Order', value: '#${item['order_number']}'),
            if (totalEarned > 0) ...[
              const SizedBox(height: 4),
              _InfoRow(label: 'Total earned', value: 'ZMW ${totalEarned.toStringAsFixed(2)}'),
              _InfoRow(label: 'Queue paid', value: 'ZMW ${queuePaid.toStringAsFixed(2)}'),
              _InfoRow(
                label: 'Balance left',
                value: 'ZMW ${(availableBalance + claimAmount).toStringAsFixed(2)}',
              ),
            ],
            if (proofUrl != null) ...[
              const SizedBox(height: 8),
              _ProofThumbnail(url: proofUrl),
            ],
            if (isOverpay) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_rounded, color: Colors.red.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ZMW ${queuePaid.toStringAsFixed(2)} was already paid from the payout queue. '
                        'Paying this claim of ZMW ${claimAmount.toStringAsFixed(2)} would be a double payment — '
                        'the person has already received more than they earned.',
                        style: TextStyle(fontSize: 12, color: Colors.red.shade800, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (hasQueuePayment) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, color: Colors.orange.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Note: ZMW ${queuePaid.toStringAsFixed(2)} was already paid to this person '
                        'directly from the payout queue. This claim of ZMW ${claimAmount.toStringAsFixed(2)} '
                        'is still within their available balance — safe to pay.',
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade900, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _markPaid,
                style: isOverpay
                    ? FilledButton.styleFrom(backgroundColor: Colors.red.shade600)
                    : null,
                icon: _loading
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(isOverpay ? Icons.warning_rounded : Icons.check_circle_outline),
                label: Text(isOverpay ? 'Mark Paid (double-pay risk)' : 'Mark Paid'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────

class _CopyPhoneRow extends StatelessWidget {
  final String phone;
  const _CopyPhoneRow({required this.phone});

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (context.mounted) {
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              'Phone',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _copy(context),
              child: Row(
                children: [
                  Text(
                    phone,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.copy_rounded,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountBadge extends StatelessWidget {
  final String amount;
  const _AmountBadge({required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        amount,
        style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold),
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

String _triggerLabel(String event) {
  switch (event) {
    case 'pickup_qr': return 'Pickup QR';
    case 'dropoff_qr': return 'Dropoff QR';
    case 'manual': return 'Claim';
    default: return event;
  }
}

class _TriggerBadge extends StatelessWidget {
  final String label;
  const _TriggerBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(color: Colors.blue.shade800, fontSize: 11, fontWeight: FontWeight.w600)),
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
            title: const Text('Payment Receipt'),
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
              placeholder: (_, __) => const SizedBox(width: 64, height: 64, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              errorWidget: (_, __, ___) => const SizedBox(width: 64, height: 64, child: Icon(Icons.broken_image_outlined)),
            ),
          ),
          const SizedBox(width: 10),
          const Text('Payment receipt attached — tap to view', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _EmptyCenter extends StatelessWidget {
  final String label;
  const _EmptyCenter({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 56, color: Colors.green),
          const SizedBox(height: 8),
          Text(label),
        ],
      ),
    );
  }
}

class _RetryCenter extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _RetryCenter({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

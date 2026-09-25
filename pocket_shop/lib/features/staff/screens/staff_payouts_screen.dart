import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/staff_service.dart';
import '../widgets/staff_widgets.dart';

final _sellerQueueProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return StaffService().getPayoutQueue(role: 'seller');
});

final _riderQueueProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return StaffService().getPayoutQueue(role: 'delivery');
});

final _earningsClaimsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return StaffService().getWithdrawals();
});

final _failedPayoutsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return StaffService().getFailedPayouts();
});

/// Which tab the Payouts screen should show. The dashboard cards set this
/// before switching to the Payouts tab, so "Failed payouts" lands on Failed.
final staffPayoutsTabProvider = StateProvider<int>((ref) => 0);

// Tab positions, so other screens can deep-link into one.
const staffPayoutsTabSellers = 0;
const staffPayoutsTabClaims = 2;
const staffPayoutsTabFailed = 3;

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
    _tabs = TabController(length: 4, vsync: this, initialIndex: ref.read(staffPayoutsTabProvider));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _refreshAll() {
    ref.invalidate(_sellerQueueProvider);
    ref.invalidate(_riderQueueProvider);
    ref.invalidate(_earningsClaimsProvider);
    ref.invalidate(_failedPayoutsProvider);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(staffPayoutsTabProvider, (_, next) {
      if (next != _tabs.index) _tabs.animateTo(next);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payouts'),
        centerTitle: false,
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Sellers'),
            Tab(text: 'Riders'),
            Tab(text: 'Earnings Claims'),
            Tab(text: 'Failed'),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _refreshAll),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _PayoutList(providerListen: _sellerQueueProvider, roleLabel: 'Seller'),
          _PayoutList(providerListen: _riderQueueProvider, roleLabel: 'Rider'),
          _ClaimsList(providerListen: _earningsClaimsProvider),
          _FailedList(providerListen: _failedPayoutsProvider, onRequeued: _refreshAll),
        ],
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────

double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

Widget _actionSpinner() => const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );

Widget _amountBadge(String amount) => StaffBadge(
      label: amount,
      background: Colors.orange.shade100,
      foreground: Colors.orange.shade800,
    );

String _triggerLabel(String event) {
  switch (event) {
    case 'pickup_qr':
      return 'Pickup QR';
    case 'dropoff_qr':
      return 'Dropoff QR';
    case 'manual':
      return 'Claim';
    default:
      return event;
  }
}

/// Wraps a list tab: loading / error / empty / pull-to-refresh, identically
/// for every tab.
class _TabList extends ConsumerWidget {
  final AutoDisposeFutureProvider<List<Map<String, dynamic>>> providerListen;
  final String emptyLabel;
  final Widget Function(Map<String, dynamic> item) itemBuilder;

  const _TabList({required this.providerListen, required this.emptyLabel, required this.itemBuilder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(providerListen);
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => StaffRetryCenter(
        message: StaffService.errorMessage(e, fallback: 'Could not load this list. Check your connection.'),
        onRetry: () => ref.invalidate(providerListen),
      ),
      data: (items) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(providerListen),
        // Always scrollable, so pull-to-refresh also works on an empty list.
        child: items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [SizedBox(height: 320, child: StaffEmptyCenter(label: emptyLabel))],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (context, i) => itemBuilder(items[i]),
              ),
      ),
    );
  }
}

// ── Payout queue tabs (per-order payouts after QR scan) ───────────────────

class _PayoutList extends ConsumerWidget {
  final AutoDisposeFutureProvider<List<Map<String, dynamic>>> providerListen;
  final String roleLabel;

  const _PayoutList({required this.providerListen, required this.roleLabel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _TabList(
      providerListen: providerListen,
      emptyLabel: 'No pending $roleLabel payouts',
      itemBuilder: (item) => _PayoutCard(item: item, onPaid: () => ref.invalidate(providerListen)),
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

  Future<void> _markPaid() async {
    final item = widget.item;
    final proof = await askManualSendProof(
      context,
      title: 'Mark as paid?',
      message: 'Confirm you sent ZMW ${item['amount']} to '
          '${item['recipient_name']} (${item['recipient_phone']}).',
    );
    if (proof == null) return;

    setState(() => _loading = true);
    try {
      await StaffService().markPaid(
        item['transaction_id'] as String,
        notes: proof.notes,
        proofImagePath: proof.proofImagePath,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Marked as paid'), backgroundColor: Colors.green),
        );
      }
      widget.onPaid();
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
    final proofUrl = item['proof_image_url'] as String?;
    final network = (item['provider_label'] as String?) ?? (item['provider'] as String? ?? '');

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
                StaffBadge(
                  label: _triggerLabel(item['trigger_event'] as String? ?? ''),
                  background: Colors.blue.shade50,
                  foreground: Colors.blue.shade800,
                ),
                const SizedBox(width: 8),
                _amountBadge('ZMW ${item['amount']}'),
              ],
            ),
            const SizedBox(height: 8),
            StaffInfoRow(label: 'Phone', value: item['recipient_phone'] as String? ?? '', copyable: true),
            StaffInfoRow(label: 'Order', value: '#${item['order_number']}'),
            StaffInfoRow(label: 'Network', value: network),
            if ((item['payout_notes'] as String? ?? '').isNotEmpty)
              StaffInfoRow(label: 'Notes', value: item['payout_notes'] as String),
            if (proofUrl != null) ...[
              const SizedBox(height: 8),
              StaffProofThumbnail(url: proofUrl),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _markPaid,
                icon: _loading ? _actionSpinner() : const Icon(Icons.check_circle_outline),
                label: const Text('Mark Paid'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Earnings claims tab (withdrawals, mobile money and bank) ──────────────

class _ClaimsList extends ConsumerWidget {
  final AutoDisposeFutureProvider<List<Map<String, dynamic>>> providerListen;

  const _ClaimsList({required this.providerListen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _TabList(
      providerListen: providerListen,
      emptyLabel: 'No pending earnings claims',
      itemBuilder: (item) => _ClaimCard(item: item, onChanged: () => ref.invalidate(providerListen)),
    );
  }
}

class _ClaimCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onChanged;

  const _ClaimCard({required this.item, required this.onChanged});

  @override
  State<_ClaimCard> createState() => _ClaimCardState();
}

class _ClaimCardState extends State<_ClaimCard> {
  bool _loading = false;

  void _snack(String message, {required bool ok}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: ok ? Colors.green : Colors.red),
    );
  }

  bool get _isBank => widget.item['payment_method'] == 'bank';

  String get _destination {
    final bank = widget.item['bank'] as Map<String, dynamic>?;
    if (_isBank && bank != null) {
      return '${bank['bank_name']} ${bank['account_number']} (${bank['account_name']})';
    }
    return '${widget.item['recipient_name']} (${widget.item['recipient_phone']})';
  }

  Future<void> _markPaid() async {
    final proof = await askManualSendProof(
      context,
      title: 'Confirm earnings paid?',
      message: 'Confirm you sent ZMW ${widget.item['amount']} to $_destination.',
    );
    if (proof == null) return;

    setState(() => _loading = true);
    try {
      await StaffService().markPaid(
        widget.item['transaction_id'] as String,
        notes: proof.notes,
        proofImagePath: proof.proofImagePath,
      );
      _snack('Marked as paid', ok: true);
      widget.onChanged();
    } catch (e) {
      _snack(StaffService.errorMessage(e), ok: false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendViaLenco() async {
    final bank = widget.item['bank'] as Map<String, dynamic>?;
    final mismatch = _isBank && bank != null && bank['name_matches'] != true;

    final ok = await askStaffConfirm(
      context,
      title: mismatch ? 'Name does not match — send anyway?' : 'Send via Lenco?',
      message: mismatch
          ? 'The bank says this account belongs to "${bank['account_name']}", which does not match '
              '${widget.item['recipient_name']}. Only send if you have checked it is genuinely theirs.\n\n'
              'Send ZMW ${widget.item['amount']} to $_destination?'
          : 'Send ZMW ${widget.item['amount']} from the Lenco account to $_destination. This cannot be undone.',
      confirmLabel: mismatch ? 'Send anyway' : 'Send',
      destructive: mismatch,
    );
    if (!ok) return;

    setState(() => _loading = true);
    try {
      final result = await StaffService().sendViaLenco(
        widget.item['transaction_id'] as String,
        confirmNameMismatch: mismatch,
      );
      _snack(result['message']?.toString() ?? 'Sent.', ok: true);
    } catch (e) {
      _snack(StaffService.errorMessage(e, fallback: 'Could not send this payout. Please try again.'), ok: false);
    } finally {
      if (mounted) setState(() => _loading = false);
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final role = item['recipient_role'] as String? ?? '';
    final roleColor = role == 'seller' ? Colors.indigo : Colors.teal;
    final inFlight = item['status'] == 'accepted';
    final bank = item['bank'] as Map<String, dynamic>?;
    final canSendViaLenco = item['can_send_via_lenco'] == true && !inFlight;
    final failure = (item['failure_message'] as String? ?? '').trim();

    final amount = _num(item['amount']);
    final fee = _num(item['fee_deducted']);
    final queuePaid = _num(item['queue_already_paid']);
    // `available_balance` already has every pending claim (this one included)
    // taken off, so it is what the person has left AFTER this claim is paid.
    // (The screen used to add the claim back and call that "Balance left".)
    final balanceAfter = _num(item['available_balance']);
    final totalEarned = _num(item['total_earned']);
    final proofUrl = item['proof_image_url'] as String?;

    final isOverpay = balanceAfter < 0;
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
                StaffBadge(
                  label: role == 'seller' ? 'Seller' : 'Rider',
                  background: roleColor.shade100,
                  foreground: roleColor.shade800,
                ),
                const SizedBox(width: 8),
                _amountBadge('ZMW ${item['amount']}'),
              ],
            ),
            const SizedBox(height: 8),
            if (_isBank && bank != null) ...[
              StaffInfoRow(label: 'Bank', value: bank['bank_name'] as String? ?? ''),
              StaffInfoRow(label: 'Account', value: bank['account_number'] as String? ?? '', copyable: true),
              StaffInfoRow(label: 'Account name', value: bank['account_name'] as String? ?? ''),
              if (fee > 0) ...[
                StaffInfoRow(label: 'Requested', value: 'ZMW ${(amount + fee).toStringAsFixed(2)}'),
                StaffInfoRow(label: 'Bank fee', value: '− ZMW ${fee.toStringAsFixed(2)}'),
                StaffInfoRow(label: 'You send', value: 'ZMW ${amount.toStringAsFixed(2)}'),
              ],
              if (bank['name_matches'] != true)
                StaffCallout(
                  text: 'The account holder name does not match ${item['recipient_name']}. '
                      'Check it before paying.',
                ),
            ] else ...[
              StaffInfoRow(label: 'Phone', value: item['recipient_phone'] as String? ?? '', copyable: true),
              StaffInfoRow(
                label: 'Network',
                value: (item['provider_label'] as String?) ?? (item['provider'] as String? ?? ''),
              ),
            ],
            StaffInfoRow(label: 'Order', value: '#${item['order_number']}'),
            if (totalEarned > 0) ...[
              const SizedBox(height: 4),
              StaffInfoRow(label: 'Total earned', value: 'ZMW ${totalEarned.toStringAsFixed(2)}'),
              StaffInfoRow(label: 'Queue paid', value: 'ZMW ${queuePaid.toStringAsFixed(2)}'),
              StaffInfoRow(label: 'Left after', value: 'ZMW ${balanceAfter.toStringAsFixed(2)}'),
            ],
            if (proofUrl != null) ...[
              const SizedBox(height: 8),
              StaffProofThumbnail(url: proofUrl),
            ],
            if (failure.isNotEmpty && !inFlight)
              StaffCallout(text: 'Last attempt failed: $failure'),
            if (isOverpay)
              StaffCallout(
                text: 'The earnings on record do not cover every pending claim from this person '
                    '(short by ZMW ${(-balanceAfter).toStringAsFixed(2)}). '
                    'ZMW ${queuePaid.toStringAsFixed(2)} was already paid from the payout queue. '
                    'Paying this claim of ZMW ${(amount + fee).toStringAsFixed(2)} risks paying them twice.',
              )
            else if (hasQueuePayment)
              StaffCallout(
                text: 'ZMW ${queuePaid.toStringAsFixed(2)} was already paid to this person from the payout queue. '
                    'This claim is still within their earnings, so it is safe to pay.',
                color: Colors.orange,
                icon: Icons.info_outline_rounded,
              ),
            const SizedBox(height: 12),
            if (inFlight)
              const StaffCallout(
                text: 'Sent through Lenco — waiting for confirmation. It disappears from this list once paid.',
                color: Colors.blue,
                icon: Icons.hourglass_top_rounded,
              )
            else ...[
              if (canSendViaLenco)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _sendViaLenco,
                    icon: _loading ? _actionSpinner() : const Icon(Icons.send_rounded),
                    label: const Text('Send via Lenco'),
                  ),
                ),
              if (canSendViaLenco) const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: canSendViaLenco
                    ? OutlinedButton.icon(
                        onPressed: _loading ? null : _markPaid,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Mark paid (sent by hand)'),
                      )
                    : FilledButton.icon(
                        onPressed: _loading ? null : _markPaid,
                        style: isOverpay ? FilledButton.styleFrom(backgroundColor: Colors.red.shade600) : null,
                        icon: _loading
                            ? _actionSpinner()
                            : Icon(isOverpay ? Icons.warning_rounded : Icons.check_circle_outline),
                        label: Text(isOverpay ? 'Mark Paid (double-pay risk)' : 'Mark Paid'),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Failed payouts tab ────────────────────────────────────────────────────

class _FailedList extends ConsumerWidget {
  final AutoDisposeFutureProvider<List<Map<String, dynamic>>> providerListen;
  final VoidCallback onRequeued;

  const _FailedList({required this.providerListen, required this.onRequeued});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _TabList(
      providerListen: providerListen,
      emptyLabel: 'No failed payouts',
      itemBuilder: (item) => _FailedCard(item: item, onRequeued: onRequeued),
    );
  }
}

class _FailedCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onRequeued;

  const _FailedCard({required this.item, required this.onRequeued});

  @override
  State<_FailedCard> createState() => _FailedCardState();
}

class _FailedCardState extends State<_FailedCard> {
  bool _loading = false;

  Future<void> _requeue() async {
    final item = widget.item;
    final ok = await askStaffConfirm(
      context,
      title: 'Put back in the payout queue?',
      message: 'It will appear under ${item['recipient_role'] == 'seller' ? 'Sellers' : 'Riders'} so you can pay '
          '${item['recipient_name']} ZMW ${item['amount']} by hand.',
      confirmLabel: 'Requeue',
    );
    if (!ok) return;

    setState(() => _loading = true);
    try {
      await StaffService().requeuePayout(item['transaction_id'] as String);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Back in the payout queue'), backgroundColor: Colors.green),
        );
      }
      widget.onRequeued();
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
    final canRequeue = item['can_requeue'] == true;

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
                StaffBadge(
                  label: _triggerLabel(item['trigger_event'] as String? ?? ''),
                  background: Colors.blue.shade50,
                  foreground: Colors.blue.shade800,
                ),
                const SizedBox(width: 8),
                _amountBadge('ZMW ${item['amount']}'),
              ],
            ),
            const SizedBox(height: 8),
            if ((item['recipient_phone'] as String? ?? '').isNotEmpty)
              StaffInfoRow(label: 'Phone', value: item['recipient_phone'] as String, copyable: true),
            StaffInfoRow(label: 'Order', value: '#${item['order_number']}'),
            StaffInfoRow(label: 'Via', value: item['provider_label'] as String? ?? ''),
            StaffCallout(text: 'Failed: ${item['failure_message']}'),
            const SizedBox(height: 12),
            if (canRequeue)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _requeue,
                  icon: _loading ? _actionSpinner() : const Icon(Icons.replay_rounded),
                  label: const Text('Put back in payout queue'),
                ),
              )
            else
              const StaffCallout(
                text: 'This was a withdrawal request. The money went back to their earnings, '
                    'so they can simply request it again.',
                color: Colors.blue,
                icon: Icons.info_outline_rounded,
              ),
          ],
        ),
      ),
    );
  }
}

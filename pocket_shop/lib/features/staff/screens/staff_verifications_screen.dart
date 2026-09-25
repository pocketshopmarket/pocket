import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/staff_service.dart';
import '../widgets/staff_widgets.dart';

final _verificationsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return StaffService().getVerifications();
});

class StaffVerificationsScreen extends ConsumerWidget {
  const StaffVerificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_verificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verifications'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(_verificationsProvider),
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => StaffRetryCenter(
          message: StaffService.errorMessage(e, fallback: 'Could not load verifications. Check your connection.'),
          onRetry: () => ref.invalidate(_verificationsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_user_outlined, size: 56, color: Colors.green),
                  SizedBox(height: 8),
                  Text('No pending verifications'),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_verificationsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, i) => _VerificationCard(
                item: items[i],
                onAction: () => ref.invalidate(_verificationsProvider),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VerificationCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onAction;

  const _VerificationCard({required this.item, required this.onAction});

  @override
  State<_VerificationCard> createState() => _VerificationCardState();
}

class _VerificationCardState extends State<_VerificationCard> {
  bool _loading = false;

  String _typeLabel(String type) {
    switch (type) {
      case 'seller_tier1':
        return 'Seller Tier 1';
      case 'seller_tier2':
        return 'Seller Tier 2';
      case 'delivery':
        return 'Delivery Agent';
      default:
        return type;
    }
  }

  Future<void> _approve() async {
    final confirm = await askStaffConfirm(
      context,
      title: 'Approve verification?',
      message: 'Approve ${widget.item['user_name']} for '
          '${_typeLabel(widget.item['verification_type'] as String? ?? '')}?',
      confirmLabel: 'Approve',
    );
    if (!confirm) return;
    setState(() => _loading = true);
    try {
      await StaffService().approveVerification(widget.item['id'] as int);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Approved'), backgroundColor: Colors.green),
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
      builder: (_) => _RejectReasonDialog(userName: '${widget.item['user_name']}'),
    );
    if (reason == null) return;
    setState(() => _loading = true);
    try {
      await StaffService().rejectVerification(widget.item['id'] as int, reason: reason);
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
    final type = item['verification_type'] as String? ?? '';
    final isDelivery = type == 'delivery';

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
                    item['user_name'] as String? ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _typeLabel(type),
                    style: TextStyle(color: Colors.blue.shade800, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _InfoRow(label: 'Phone', value: item['user_phone'] as String? ?? ''),
            if (!isDelivery && (item['shop_name'] as String? ?? '').isNotEmpty)
              _InfoRow(label: 'Shop', value: item['shop_name'] as String? ?? ''),
            if (!isDelivery && (item['nrc_number'] as String? ?? '').isNotEmpty)
              _InfoRow(label: 'NRC', value: item['nrc_number'] as String? ?? ''),
            if (isDelivery && (item['vehicle_type'] as String? ?? '').isNotEmpty)
              _InfoRow(label: 'Vehicle', value: item['vehicle_type'] as String? ?? ''),
            if (isDelivery && (item['license_number'] as String? ?? '').isNotEmpty)
              _InfoRow(label: 'License', value: item['license_number'] as String? ?? ''),
            if ((item['submitted_at'] as String? ?? '').isNotEmpty)
              _InfoRow(
                label: 'Submitted',
                value: (item['submitted_at'] as String).split('T').first,
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


/// Asks why a verification is being rejected. The applicant reads this, so it
/// is required. The dialog owns (and disposes) its own text controller.
class _RejectReasonDialog extends StatefulWidget {
  final String userName;
  const _RejectReasonDialog({required this.userName});

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
      title: const Text('Reject verification'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reject ${widget.userName}? They will see your reason.'),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            autofocus: true,
            maxLines: 2,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Reason (required)',
              hintText: 'e.g. NRC photo is blurry, please retake it',
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

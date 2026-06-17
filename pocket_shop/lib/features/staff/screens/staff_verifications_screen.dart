import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/staff_service.dart';

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
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 8),
              Text(e.toString()),
              TextButton(
                onPressed: () => ref.invalidate(_verificationsProvider),
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Verification?'),
        content: Text(
          'Approve ${widget.item['user_name']} for '
          '${_typeLabel(widget.item['verification_type'] as String? ?? '')}?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve')),
        ],
      ),
    );
    if (confirm != true) return;
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
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reject() async {
    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Verification'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Reject ${widget.item['user_name']}?'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _loading = true);
    try {
      await StaffService().rejectVerification(
        widget.item['id'] as int,
        reason: reasonController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rejected'), backgroundColor: Colors.orange),
        );
        widget.onAction();
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
            if (!isDelivery && item['shop_name'] != null)
              _InfoRow(label: 'Shop', value: item['shop_name'] as String),
            if (!isDelivery && (item['nrc_number'] as String? ?? '').isNotEmpty)
              _InfoRow(label: 'NRC', value: item['nrc_number'] as String),
            if (isDelivery && item['vehicle_type'] != null)
              _InfoRow(label: 'Vehicle', value: item['vehicle_type'] as String),
            if (isDelivery && (item['license_number'] as String? ?? '').isNotEmpty)
              _InfoRow(label: 'License', value: item['license_number'] as String),
            if (item['submitted_at'] != null)
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

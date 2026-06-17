import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_service.dart';

class CancellationRequestsScreen extends ConsumerStatefulWidget {
  const CancellationRequestsScreen({super.key});

  @override
  ConsumerState<CancellationRequestsScreen> createState() =>
      _CancellationRequestsScreenState();
}

class _CancellationRequestsScreenState
    extends ConsumerState<CancellationRequestsScreen> {
  List<Map<String, dynamic>> _requests = [];
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
      final res = await api.get(AppConstants.cancellationRequestsEndpoint);
      final raw = res.data;
      final list = raw is List
          ? raw
          : (raw is Map && raw['results'] is List
              ? raw['results'] as List
              : <dynamic>[]);
      if (mounted) {
        setState(() => _requests = list.cast<Map<String, dynamic>>());
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _respond(
      Map<String, dynamic> request, String action, String role) async {
    final noteCtrl = TextEditingController();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              action == 'approve'
                  ? 'Approve cancellation?'
                  : action == 'escalate'
                      ? 'Escalate to admin?'
                      : 'Reject cancellation?',
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700),
            ),
            if (action == 'approve')
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'The order will be cancelled and the buyer will be refunded.',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                ),
              ),
            if (action == 'reject')
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'The buyer can escalate to admin if they disagree.',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                ),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: noteCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'Add a message for the buyer...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: action == 'approve'
                          ? AppTheme.success
                          : action == 'escalate'
                              ? AppTheme.warning
                              : AppTheme.error,
                    ),
                    child: Text(action == 'approve'
                        ? 'Approve'
                        : action == 'escalate'
                            ? 'Escalate'
                            : 'Reject'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final api = ApiService();
      await api.post(
        '${AppConstants.cancellationRequestsEndpoint}${request['id']}/respond/',
        data: {'action': action, 'note': noteCtrl.text.trim()},
      );
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Done'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(userProvider)?.role ?? 'buyer';
    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('Cancellation requests'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryCyan))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: AppTheme.textSecondary)),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _requests.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cancel_outlined,
                              size: 48, color: AppTheme.textSecondary),
                          SizedBox(height: 12),
                          Text('No cancellation requests',
                              style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 15)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _requests.length,
                      itemBuilder: (_, i) => _CancellationCard(
                        request: _requests[i],
                        role: role,
                        onRespond: (action) =>
                            _respond(_requests[i], action, role),
                      ),
                    ),
    );
  }
}

class _CancellationCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final String role;
  final void Function(String action) onRespond;

  const _CancellationCard(
      {required this.request,
      required this.role,
      required this.onRespond});

  Color _statusColor(String status) {
    switch (status) {
      case 'pending_seller':
        return AppTheme.warning;
      case 'approved_by_seller':
      case 'approved_by_admin':
        return AppTheme.success;
      case 'rejected_by_seller':
      case 'rejected_by_admin':
        return AppTheme.error;
      case 'escalated':
        return AppTheme.accentBlue;
      default:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = request['status']?.toString() ?? '';
    final statusDisplay =
        request['status_display']?.toString() ?? status;
    final orderNo = request['order_number']?.toString() ?? '';
    final amount = request['order_total']?.toString() ?? '';
    final reason = request['reason']?.toString() ?? '';
    final buyerName = request['buyer_name']?.toString() ?? '';
    final sellerNote = request['seller_note']?.toString() ?? '';
    final adminNote = request['admin_note']?.toString() ?? '';
    final date =
        request['created_at']?.toString().substring(0, 10) ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 6,
              offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(orderNo,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppTheme.textPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor(status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(statusDisplay,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _statusColor(status))),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (role != 'buyer')
            Text('Buyer: $buyerName',
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
          Text('ZMW $amount · $date',
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          Text('Reason: $reason',
              style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textPrimary,
                  height: 1.35)),
          if (sellerNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Seller note: $sellerNote',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.3)),
          ],
          if (adminNote.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Admin note: $adminNote',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.3)),
          ],
          // Seller actions
          if (role == 'seller' && status == 'pending_seller') ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => onRespond('approve'),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Approve'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.success,
                      side: const BorderSide(color: AppTheme.success)),
                ),
                OutlinedButton.icon(
                  onPressed: () => onRespond('escalate'),
                  icon: const Icon(Icons.upload_outlined, size: 16),
                  label: const Text('Escalate'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentBlue,
                      side: const BorderSide(color: AppTheme.accentBlue)),
                ),
                OutlinedButton.icon(
                  onPressed: () => onRespond('reject'),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      side: const BorderSide(color: AppTheme.error)),
                ),
              ],
            ),
          ],
          // Admin actions
          if ((role == 'admin' || role == 'staff') &&
              (status == 'escalated' ||
                  status == 'rejected_by_seller')) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => onRespond('approve'),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Approve & refund'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.success,
                      side: const BorderSide(color: AppTheme.success)),
                ),
                OutlinedButton.icon(
                  onPressed: () => onRespond('reject'),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      side: const BorderSide(color: AppTheme.error)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

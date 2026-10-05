import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/transport_request.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/orders_provider.dart';
import '../../../providers/payment_methods_provider.dart';
import '../../../providers/transport_requests_provider.dart';
import '../../../providers/payment_options_provider.dart';
import '../../../services/card_payment_service.dart';
import '../../buyer/screens/card_checkout_screen.dart';
import '../../buyer/widgets/card_payment_panel.dart';

class TransportRequestsScreen extends ConsumerWidget {
  const TransportRequestsScreen({super.key});

  Future<void> _propose(BuildContext context, WidgetRef ref, TransportRequest tr) async {
    final methodCtrl = TextEditingController();
    final feeCtrl = TextEditingController();
    final result = await showModalBottomSheet<bool>(
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
            const Text(
              'Propose transport',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Tell the buyer how you\'ll get "${tr.productName ?? 'this item'}" to them and what it will cost.',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: methodCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Transport method',
                hintText: 'e.g. Power Tools bus to Lusaka, collect at terminus',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: feeCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Fee (ZMW)',
                prefixText: 'ZMW ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final fee = double.tryParse(feeCtrl.text.trim());
                      if (methodCtrl.text.trim().isEmpty || fee == null || fee <= 0) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Enter a method and a valid fee.')),
                        );
                        return;
                      }
                      Navigator.pop(ctx, true);
                    },
                    child: const Text('Send proposal'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (result != true || !context.mounted) return;
    final fee = double.tryParse(feeCtrl.text.trim()) ?? 0;
    try {
      await ref.read(transportServiceProvider).propose(
            id: tr.id,
            method: methodCtrl.text.trim(),
            fee: fee,
          );
      ref.invalidate(transportRequestsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Proposal sent'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (context.mounted) {
        final msg = e is DioException
            ? (ref.read(transportServiceProvider).extractErrorMessage(e) ?? 'Could not send the proposal.')
            : 'Could not send the proposal.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  Future<void> _decline(BuildContext context, WidgetRef ref, TransportRequest tr) async {
    final reasonCtrl = TextEditingController();
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
            const Text(
              'Decline this request?',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'The buyer will be told you can\'t arrange transport for this order.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
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
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
                    child: const Text('Decline'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(transportServiceProvider).decline(id: tr.id, reason: reasonCtrl.text.trim());
      ref.invalidate(transportRequestsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request declined')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        final msg = e is DioException
            ? (ref.read(transportServiceProvider).extractErrorMessage(e) ?? 'Could not decline the request.')
            : 'Could not decline the request.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  Future<void> _acceptAndPay(BuildContext context, WidgetRef ref, TransportRequest tr) async {
    await ref.read(paymentMethodsProvider.notifier).load();
    if (!context.mounted) return;
    var paymentOptions = const PaymentOptions();
    try {
      paymentOptions = await ref.read(paymentOptionsProvider.future);
    } catch (_) {
      // Can't tell -> don't offer cards; mobile money always works.
    }
    if (!context.mounted) return;

    final user = ref.read(userProvider);
    String selectedProvider = 'AIRTEL_OAPI_ZMB';
    String payMethod = 'mobile_money';
    final cardDraft = CardPaymentDraft();
    final payerNumberController = TextEditingController();

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Accept & pay',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryCyan.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr.proposedMethod,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Transport fee: ZMW ${(tr.proposedFee ?? 0).toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (paymentOptions.cardEnabled) ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => setModalState(() => payMethod = 'mobile_money'),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: payMethod == 'mobile_money'
                                    ? AppTheme.primaryCyan.withValues(alpha: 0.10)
                                    : null,
                              ),
                              child: const Text('Mobile money'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => setModalState(() => payMethod = 'card'),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: payMethod == 'card'
                                    ? AppTheme.primaryCyan.withValues(alpha: 0.10)
                                    : null,
                              ),
                              child: const Text('Card'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (payMethod == 'card')
                      CardPaymentPanel(
                        draft: cardDraft,
                        options: paymentOptions,
                        orderTotal: (tr.productPrice ?? 0) * tr.quantity + (tr.proposedFee ?? 0),
                        initialPhone: (user?.phoneNumber ?? '').replaceFirst('+260', ''),
                        service: ref.read(cardPaymentServiceProvider),
                        onChanged: () => setModalState(() {}),
                      )
                    else ...[
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Airtel'),
                            selected: selectedProvider == 'AIRTEL_OAPI_ZMB',
                            onSelected: (_) => setModalState(() => selectedProvider = 'AIRTEL_OAPI_ZMB'),
                          ),
                          ChoiceChip(
                            label: const Text('MTN'),
                            selected: selectedProvider == 'MTN_MOMO_ZMB',
                            onSelected: (_) => setModalState(() => selectedProvider = 'MTN_MOMO_ZMB'),
                          ),
                          ChoiceChip(
                            label: const Text('Zamtel'),
                            selected: selectedProvider == 'ZAMTEL_MONEY_ZMB',
                            onSelected: (_) => setModalState(() => selectedProvider = 'ZAMTEL_MONEY_ZMB'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: payerNumberController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Mobile money number',
                          hintText: '97 XXX XXXX',
                          prefixText: '+260 ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          if (payMethod == 'card') {
                            if (!cardDraft.isReady) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Check your refund number and accept the terms.')),
                              );
                              return;
                            }
                          } else if (payerNumberController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Enter your mobile money number.')),
                            );
                            return;
                          } else {
                            var num = payerNumberController.text.trim();
                            num = num.replaceAll(RegExp(r'[\s\-()]'), '');
                            if (num.startsWith('0')) {
                              num = '+260${num.substring(1)}';
                            } else if (!num.startsWith('+')) {
                              num = '+260$num';
                            }
                            payerNumberController.text = num;
                          }
                          Navigator.pop(ctx, payMethod);
                        },
                        child: const Text('Accept & pay'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (action == null || !context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('Preparing…', style: TextStyle(color: Colors.white, fontSize: 15)),
            ],
          ),
        ),
      ),
    );

    try {
      final order = await ref.read(transportServiceProvider).accept(tr.id);
      Map<String, dynamic>? payment;
      if (action == 'card') {
        final session = await ref.read(cardPaymentServiceProvider).initiate(
              orderNumber: order.orderNumber,
              refundPhone: cardDraft.verified!.phone,
            );
        payment = {'checkout_url': session.checkoutUrl, 'amount_charged': session.amount};
      } else {
        payment = await ref.read(orderServiceProvider).initiatePayment(
              orderNumber: order.orderNumber,
              provider: selectedProvider,
              payerNumber: payerNumberController.text.trim(),
            );
      }

      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      if (!context.mounted) return;

      ref.invalidate(transportRequestsProvider);
      ref.invalidate(buyerOrdersProvider);

      final checkoutUrl = payment['checkout_url']?.toString() ?? '';
      if (checkoutUrl.isNotEmpty) {
        await Navigator.of(context).push<CardCheckoutResult>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => CardCheckoutScreen(checkoutUrl: checkoutUrl),
          ),
        );
        if (!context.mounted) return;
      }
      final amountCharged = payment['amount_charged']?.toString() ?? '';
      context.go(
        '/buyer/payment-pending'
        '?order=${Uri.encodeComponent(order.orderNumber)}'
        '&provider=${Uri.encodeComponent(action == 'card' ? 'LENCO_CARD' : selectedProvider)}'
        '&amount=${Uri.encodeComponent(amountCharged)}'
        '&delivery=true',
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      if (!context.mounted) return;
      String msg;
      if (e is CardPaymentException) {
        msg = e.toString();
      } else if (e is DioException) {
        msg = ref.read(transportServiceProvider).extractErrorMessage(e) ?? 'Could not complete payment.';
      } else {
        msg = 'Could not complete payment.';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      ref.invalidate(transportRequestsProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(userProvider)?.role ?? 'buyer';
    final async = ref.watch(transportRequestsProvider);
    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('Transport requests'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(transportRequestsProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryCyan),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Could not load transport requests.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(transportRequestsProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (requests) => requests.isEmpty
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_shipping_outlined, size: 48, color: AppTheme.textSecondary),
                    SizedBox(height: 12),
                    Text('No transport requests', style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: requests.length,
                itemBuilder: (_, i) => _TransportCard(
                  tr: requests[i],
                  role: role,
                  onPropose: () => _propose(context, ref, requests[i]),
                  onDecline: () => _decline(context, ref, requests[i]),
                  onAccept: () => _acceptAndPay(context, ref, requests[i]),
                ),
              ),
      ),
    );
  }
}

class _TransportCard extends StatelessWidget {
  final TransportRequest tr;
  final String role;
  final VoidCallback onPropose;
  final VoidCallback onDecline;
  final VoidCallback onAccept;

  const _TransportCard({
    required this.tr,
    required this.role,
    required this.onPropose,
    required this.onDecline,
    required this.onAccept,
  });

  Color _statusColor() {
    switch (tr.status) {
      case 'pending':
        return AppTheme.warning;
      case 'proposed':
        return AppTheme.accentBlue;
      case 'accepted':
        return AppTheme.success;
      case 'declined':
      case 'expired':
        return AppTheme.error;
      default:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSeller = role == 'seller';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${tr.productName ?? 'Product'} ×${tr.quantity}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor().withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tr.statusDisplay,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _statusColor()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (isSeller)
            Text('Buyer: ${tr.buyerName ?? ''}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary))
          else
            Text('Seller: ${tr.sellerName ?? ''}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          if (tr.distanceKm != null)
            Text(
              '${tr.distanceKm!.toStringAsFixed(0)} km away · ${tr.deliveryAddress}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          if (tr.isProposed || tr.status == 'accepted') ...[
            const SizedBox(height: 8),
            Text(tr.proposedMethod, style: const TextStyle(fontSize: 13, height: 1.3)),
            Text(
              'Fee: ZMW ${(tr.proposedFee ?? 0).toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
          if (tr.status == 'declined' && tr.declineReason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Reason: ${tr.declineReason}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          ],
          if (tr.status == 'expired')
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'This request expired without a response.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),
          if (isSeller && tr.isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: onPropose, child: const Text('Propose')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDecline,
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error),
                    child: const Text('Decline'),
                  ),
                ),
              ],
            ),
          ],
          if (!isSeller && tr.isProposed) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: onAccept, child: const Text('Accept & pay')),
            ),
          ],
        ],
      ),
    );
  }
}

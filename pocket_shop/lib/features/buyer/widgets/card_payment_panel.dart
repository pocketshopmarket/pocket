import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/card_payment_service.dart';

/// What the buyer has confirmed for a card payment. Lives in the checkout
/// sheet (which rebuilds freely), and the panel below fills it in.
class CardPaymentDraft {
  RefundNumberCheck? verified;
  bool acceptedTerms = false;

  /// Ready to pay only once the refund number was checked with the network
  /// AND the buyer agreed to the refund terms.
  bool get isReady => verified != null && acceptedTerms;
}

/// Step-2 content when the buyer chooses to pay by card.
///
/// A card payment can't be reversed to the card, so before paying the buyer
/// must name a mobile money number for any refund, see the name registered on
/// it, and agree to the terms. That is what lets us promise a refund within a
/// fixed number of days.
class CardPaymentPanel extends StatefulWidget {
  final CardPaymentDraft draft;
  final PaymentOptions options;
  final double orderTotal;
  final String initialPhone;
  final CardPaymentService service;
  final VoidCallback onChanged;

  const CardPaymentPanel({
    super.key,
    required this.draft,
    required this.options,
    required this.orderTotal,
    required this.initialPhone,
    required this.service,
    required this.onChanged,
  });

  @override
  State<CardPaymentPanel> createState() => _CardPaymentPanelState();
}

class _CardPaymentPanelState extends State<CardPaymentPanel> {
  late final TextEditingController _phone;
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _phone = TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final number = _phone.text.trim();
    if (number.isEmpty) {
      setState(() => _error = 'Enter the mobile money number for refunds.');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final result = await widget.service.checkRefundNumber(number);
      if (!mounted) return;
      widget.draft.verified = result;
      _phone.text = result.phone.replaceFirst('+260', '');
      setState(() => _checking = false);
    } on CardPaymentException catch (e) {
      if (!mounted) return;
      widget.draft.verified = null;
      widget.draft.acceptedTerms = false;
      setState(() {
        _checking = false;
        _error = e.message;
      });
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final verified = widget.draft.verified;
    final fee = widget.options.estimateFee(widget.orderTotal);
    final days = widget.options.refundBusinessDays;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.credit_card_rounded, size: 18, color: AppTheme.primaryCyan),
              SizedBox(width: 8),
              Text(
                'Pay by card',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Visa or Mastercard. You enter your card in a secure window on the next step.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 10),
          _note(
            Icons.receipt_long_rounded,
            'A card fee of about ZMW ${fee.toStringAsFixed(2)} is added to your total when you pay. '
            'It is charged by our payment provider and is not refundable.',
            const Color(0xFFF3F4F6),
            AppTheme.textSecondary,
          ),
          const SizedBox(height: 14),
          const Text(
            'Where should a refund go?',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            "A card payment can't be returned to your card. If your order is cancelled or a refund is approved, "
            'we send the order amount to this mobile money number within $days business days.',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            onChanged: (_) {
              // Any edit invalidates a previous check.
              if (widget.draft.verified != null) {
                widget.draft.verified = null;
                widget.draft.acceptedTerms = false;
                setState(() {});
                widget.onChanged();
              }
            },
            decoration: InputDecoration(
              labelText: 'Mobile money number for refunds',
              hintText: '97 XXX XXXX',
              prefixText: '+260 ',
              filled: true,
              fillColor: const Color(0xFFF8F8F8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.divider),
              ),
              suffixIcon: verified != null
                  ? const Icon(Icons.check_circle_rounded, color: AppTheme.success)
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          if (verified == null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _checking ? null : _check,
                icon: _checking
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.verified_user_outlined, size: 18),
                label: Text(_checking ? 'Checking…' : 'Check this number'),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            _note(Icons.error_outline_rounded, _error!, AppTheme.error.withValues(alpha: 0.08), AppTheme.error),
          ],
          if (verified != null) ...[
            _note(
              Icons.person_outline_rounded,
              'Refunds will be sent to ${verified.accountName.isEmpty ? 'this number' : verified.accountName} '
              '(${verified.network} ${verified.phone}). If that is not you, change the number.',
              AppTheme.success.withValues(alpha: 0.08),
              AppTheme.success,
            ),
            const SizedBox(height: 6),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              value: widget.draft.acceptedTerms,
              onChanged: (v) {
                setState(() => widget.draft.acceptedTerms = v == true);
                widget.onChanged();
              },
              title: Text(
                'I understand the card fee is not refunded and any refund goes to this mobile money '
                'number within $days business days.',
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _note(IconData icon, String text, Color background, Color foreground) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: foreground, height: 1.4))),
        ],
      ),
    );
  }
}

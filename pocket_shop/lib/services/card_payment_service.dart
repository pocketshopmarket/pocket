import 'package:dio/dio.dart';

import 'api_service.dart';

/// What the checkout may offer, as decided by the server (admin switch plus
/// whether card payments are configured at all).
class PaymentOptions {
  final bool cardEnabled;
  final int refundBusinessDays;
  final double feePercent;
  final double feeFixed;

  const PaymentOptions({
    this.cardEnabled = false,
    this.refundBusinessDays = 5,
    this.feePercent = 3.8,
    this.feeFixed = 1.0,
  });

  factory PaymentOptions.fromJson(Map<String, dynamic> json) => PaymentOptions(
        cardEnabled: json['card_enabled'] == true,
        refundBusinessDays: (json['card_refund_business_days'] as num?)?.toInt() ?? 5,
        feePercent: double.tryParse(json['card_fee_percent']?.toString() ?? '') ?? 3.8,
        feeFixed: double.tryParse(json['card_fee_fixed']?.toString() ?? '') ?? 1.0,
      );

  /// A rough figure so the buyer isn't surprised. The exact fee is added and
  /// shown by the card window at payment time.
  double estimateFee(double orderTotal) => orderTotal * feePercent / 100 + feeFixed;
}

/// The mobile money account a card refund would be paid to, as the network
/// itself reports it.
class RefundNumberCheck {
  final String phone; // +260…
  final String network;
  final String accountName;

  const RefundNumberCheck({required this.phone, required this.network, required this.accountName});

  factory RefundNumberCheck.fromJson(Map<String, dynamic> json) => RefundNumberCheck(
        phone: json['phone']?.toString() ?? '',
        network: json['network']?.toString() ?? '',
        accountName: json['account_name']?.toString() ?? '',
      );
}

class CardCheckoutSession {
  final String transactionId;
  final String checkoutUrl;
  final String amount;
  final int refundBusinessDays;

  const CardCheckoutSession({
    required this.transactionId,
    required this.checkoutUrl,
    required this.amount,
    required this.refundBusinessDays,
  });

  factory CardCheckoutSession.fromJson(Map<String, dynamic> json) => CardCheckoutSession(
        transactionId: json['transaction_id']?.toString() ?? '',
        checkoutUrl: json['checkout_url']?.toString() ?? '',
        amount: json['amount']?.toString() ?? '',
        refundBusinessDays: (json['refund_business_days'] as num?)?.toInt() ?? 5,
      );
}

class CardPaymentException implements Exception {
  final String message;
  const CardPaymentException(this.message);

  @override
  String toString() => message;
}

class CardPaymentService {
  final ApiService _api = ApiService();

  Future<PaymentOptions> getOptions() async {
    try {
      final res = await _api.get('payments/options/');
      return PaymentOptions.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (_) {
      // If we can't tell, don't offer cards — mobile money always works.
      return const PaymentOptions();
    }
  }

  Future<RefundNumberCheck> checkRefundNumber(String phone) async {
    try {
      final res = await _api.post('payments/card/refund-number/check/', data: {'phone': phone});
      return RefundNumberCheck.fromJson(Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      throw CardPaymentException(_message(e, 'Could not check that number. Please try again.'));
    }
  }

  Future<CardCheckoutSession> initiate({required String orderNumber, required String refundPhone}) async {
    try {
      final res = await _api.post('payments/card/initiate/', data: {
        'order_number': orderNumber,
        'refund_phone': refundPhone,
        'refund_policy_accepted': true,
      });
      return CardCheckoutSession.fromJson(Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      throw CardPaymentException(_message(e, 'Could not start the card payment. Please try again.'));
    }
  }

  static String _message(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map && data['error'] is String) return data['error'] as String;
    if (data is Map && data['detail'] is String) return data['detail'] as String;
    return fallback;
  }
}

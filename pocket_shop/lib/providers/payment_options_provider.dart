import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/card_payment_service.dart';

final cardPaymentServiceProvider = Provider<CardPaymentService>((ref) => CardPaymentService());

/// Re-read each time checkout opens, so switching cards on or off in the
/// admin takes effect without an app update.
final paymentOptionsProvider = FutureProvider.autoDispose<PaymentOptions>((ref) {
  return ref.read(cardPaymentServiceProvider).getOptions();
});

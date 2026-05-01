import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

class BuyerPaymentMethod {
  final int id;
  final String provider;
  final String providerLabel;
  final String phoneNumber;
  final bool isVerified;
  final bool isDefault;

  const BuyerPaymentMethod({
    required this.id,
    required this.provider,
    required this.providerLabel,
    required this.phoneNumber,
    this.isVerified = false,
    this.isDefault = false,
  });

  factory BuyerPaymentMethod.fromJson(Map<String, dynamic> json) {
    return BuyerPaymentMethod(
      id: json['id'] as int,
      provider: (json['provider'] ?? '').toString(),
      providerLabel: (json['provider_label'] ?? json['provider'] ?? '').toString(),
      phoneNumber: (json['account_phone'] ?? '').toString(),
      isVerified: json['is_verified'] == true,
      isDefault: json['is_default'] == true,
    );
  }
}

class PaymentMethodsNotifier extends StateNotifier<List<BuyerPaymentMethod>> {
  PaymentMethodsNotifier(this._ref, this._api) : super(const []);

  final Ref _ref;
  final ApiService _api;

  String _providerKey(String label) {
    final v = label.trim().toLowerCase();
    if (v == 'mtn_momo' || v == 'airtel_money' || v == 'zamtel') return v;
    if (v.contains('airtel')) return 'airtel_money';
    if (v.contains('zamtel')) return 'zamtel';
    return 'mtn_momo';
  }

  Future<void> load() async {
    final auth = _ref.read(authProvider);
    if (!auth.isAuthenticated || auth.user?.isBuyer != true) {
      state = const [];
      return;
    }
    try {
      final response = await _api.get(AppConstants.buyerPaymentMethodsEndpoint);
      final data = response.data;
      if (data is List) {
        state = data
            .map(
              (e) =>
                  BuyerPaymentMethod.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
      } else {
        state = const [];
      }
    } catch (_) {
      state = const [];
    }
  }

  Future<int?> addMethod({required String provider, required String phoneNumber}) async {
    final response = await _api.post(
      AppConstants.buyerPaymentMethodsEndpoint,
      data: {
        'provider': _providerKey(provider),
        'account_phone': phoneNumber,
      },
    );
    final data = response.data;
    if (data is Map<String, dynamic>) {
      final created = BuyerPaymentMethod.fromJson(data);
      state = [...state, created];
      return created.id;
    }
    await load();
    return null;
  }

  Future<void> verifyMethod(int id, String otpCode) async {
    await _api.post(
      '${AppConstants.buyerPaymentMethodsEndpoint}$id/verify/',
      data: {'otp_code': otpCode},
    );
    await load();
  }

  Future<void> setDefault(int id) async {
    await _api.patch(
      '${AppConstants.buyerPaymentMethodsEndpoint}$id/',
      data: {'is_default': true},
    );
    await load();
  }

  String? extractError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        final err = data['error'] ?? data['detail'] ?? data['message'];
        if (err != null) return err.toString();
        if (data.isNotEmpty) {
          final first = data.values.first;
          if (first is List && first.isNotEmpty) return first.first.toString();
          return first.toString();
        }
      }
      return e.message;
    }
    return e.toString();
  }
}

final paymentMethodsProvider =
    StateNotifierProvider<PaymentMethodsNotifier, List<BuyerPaymentMethod>>((ref) {
  final notifier = PaymentMethodsNotifier(ref, ApiService());
  ref.listen<AuthState>(authProvider, (prev, next) {
    if (next.isAuthenticated && next.user?.isBuyer == true) {
      notifier.load();
    }
    if (!next.isAuthenticated && (prev?.isAuthenticated ?? false)) {
      notifier.state = const [];
    }
  });
  return notifier;
});

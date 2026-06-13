import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';
import 'payment_methods_provider.dart';

class SellerPayoutMethodsNotifier extends StateNotifier<List<BuyerPaymentMethod>> {
  SellerPayoutMethodsNotifier(this._ref, this._api) : super(const []);

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
    if (!auth.isAuthenticated || (auth.user?.isSeller != true && auth.user?.isDelivery != true)) {
      state = const [];
      return;
    }
    try {
      final response = await _api.get(AppConstants.sellerPayoutMethodsEndpoint);
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
      AppConstants.sellerPayoutMethodsEndpoint,
      data: {'provider': _providerKey(provider), 'account_phone': phoneNumber},
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
      '${AppConstants.sellerPayoutMethodsEndpoint}$id/verify/',
      data: {'otp_code': otpCode},
    );
    await load();
  }

  Future<void> setDefault(int id) async {
    await _api.patch(
      '${AppConstants.sellerPayoutMethodsEndpoint}$id/',
      data: {'is_default': true},
    );
    await load();
  }

  Future<void> deleteMethod(int id) async {
    await _api.delete('${AppConstants.sellerPayoutMethodsEndpoint}$id/');
    await load();
  }

  void clear() => state = const [];

  String? extractError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        final err = data['error'] ?? data['detail'] ?? data['message'];
        if (err != null) return err.toString();
      }
      return e.message;
    }
    return e.toString();
  }
}

final sellerPayoutMethodsProvider = StateNotifierProvider<
    SellerPayoutMethodsNotifier, List<BuyerPaymentMethod>>((ref) {
  final notifier = SellerPayoutMethodsNotifier(ref, ApiService());
  ref.listen<AuthState>(authProvider, (prev, next) {
    if (next.isAuthenticated && (next.user?.isSeller == true || next.user?.isDelivery == true)) {
      notifier.load();
    }
    if (!next.isAuthenticated && (prev?.isAuthenticated ?? false)) {
      notifier.clear();
    }
  });
  return notifier;
});

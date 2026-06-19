import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Map<String, dynamic> toJson() => {
    'id': id,
    'provider': provider,
    'provider_label': providerLabel,
    'account_phone': phoneNumber,
    'is_verified': isVerified,
    'is_default': isDefault,
  };
}

class PaymentMethodsNotifier extends StateNotifier<List<BuyerPaymentMethod>> {
  PaymentMethodsNotifier(this._ref, this._api) : super(const []) {
    Future.microtask(_loadFromCache);
  }

  final Ref _ref;
  final ApiService _api;
  static const _cacheKey = 'cached_payment_methods';

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || !mounted) return;
      final List<dynamic> decoded = jsonDecode(raw);
      state = decoded
          .map((e) => BuyerPaymentMethod.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {}
  }

  Future<void> _saveToCache(List<BuyerPaymentMethod> methods) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(methods.map((m) => m.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> _clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
    } catch (_) {}
  }

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
        final methods = data
            .map((e) => BuyerPaymentMethod.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        state = methods;
        _saveToCache(methods);
      } else {
        state = const [];
      }
    } catch (_) {
      // Keep cached state on network error — don't wipe to empty
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

  Future<void> deleteMethod(int id) async {
    await _api.delete('${AppConstants.buyerPaymentMethodsEndpoint}$id/');
    await load();
  }

  void clear() {
    state = const [];
    _clearCache();
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
  final auth = ref.read(authProvider);
  if (auth.isAuthenticated && auth.user?.isBuyer == true) {
    Future.microtask(notifier.load);
  }
  ref.listen<AuthState>(authProvider, (prev, next) {
    if (next.isAuthenticated && next.user?.isBuyer == true) {
      notifier.load();
    }
    if (!next.isAuthenticated && (prev?.isAuthenticated ?? false)) {
      notifier.clear();
    }
  });
  return notifier;
});

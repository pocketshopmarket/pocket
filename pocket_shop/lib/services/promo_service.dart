import 'package:dio/dio.dart';

import '../core/constants/app_constants.dart';
import 'api_service.dart';

/// What the server will take off the buyer's current cart.
class DiscountQuote {
  /// False when a typed promo code can't be used; [error] says why and the
  /// rest of the quote is the discount the buyer still gets without it.
  final bool valid;
  final String? error;
  final double amount;

  /// '', 'welcome' or 'promo'.
  final String kind;
  final String? code;
  final String label;
  final String note;

  const DiscountQuote({
    this.valid = true,
    this.error,
    this.amount = 0,
    this.kind = '',
    this.code,
    this.label = '',
    this.note = '',
  });

  static const none = DiscountQuote();

  factory DiscountQuote.fromJson(Map<String, dynamic> json) {
    final d = json['discount'] is Map
        ? Map<String, dynamic>.from(json['discount'] as Map)
        : const <String, dynamic>{};
    return DiscountQuote(
      valid: json['valid'] != false,
      error: json['error']?.toString(),
      amount: double.tryParse('${d['amount'] ?? 0}') ?? 0,
      kind: d['kind']?.toString() ?? '',
      code: d['code']?.toString(),
      label: d['label']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
    );
  }
}

class ReferralLookup {
  final bool valid;
  final String? code;
  final String? partnerName;
  final String? error;

  const ReferralLookup({required this.valid, this.code, this.partnerName, this.error});
}

class PromoService {
  final ApiService _api = ApiService();

  /// Discount for the cart as it is on the server. With no [code] this is the
  /// welcome discount (or nothing). Never throws.
  Future<DiscountQuote> checkDiscount({String? code}) async {
    try {
      final response = await _api.post(
        AppConstants.promoCheckEndpoint,
        data: {if (code != null && code.trim().isNotEmpty) 'promo_code': code.trim()},
      );
      final data = response.data;
      if (data is Map) return DiscountQuote.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data.containsKey('discount')) {
        return DiscountQuote.fromJson(Map<String, dynamic>.from(data));
      }
      if (code != null && code.trim().isNotEmpty) {
        return const DiscountQuote(valid: false, error: "Couldn't check the code. Try again.");
      }
    } catch (_) {}
    return DiscountQuote.none;
  }

  /// Is this partner invite code real? Used at sign-up.
  Future<ReferralLookup> checkReferralCode(String code) async {
    final clean = code.trim().toUpperCase();
    try {
      final response = await _api.get('${AppConstants.referralCheckPrefix}${Uri.encodeComponent(clean)}/');
      final data = response.data;
      if (data is Map && data['valid'] == true) {
        return ReferralLookup(
          valid: true,
          code: data['code']?.toString() ?? clean,
          partnerName: data['partner_name']?.toString(),
        );
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const ReferralLookup(valid: false, error: "We couldn't find that code.");
      }
      return const ReferralLookup(valid: false, error: "Couldn't check the code. Check your internet and try again.");
    } catch (_) {}
    return const ReferralLookup(valid: false, error: "We couldn't find that code.");
  }
}

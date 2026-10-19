import 'package:dio/dio.dart';

import '../core/constants/app_constants.dart';
import '../models/seller_banner.dart';
import 'api_service.dart';

class BannerService {
  final ApiService _api = ApiService();

  /// Submits a "promote your shop" request. Creates the banner at
  /// status=pending_payment with its price already computed server-side —
  /// payment is a separate step via [initiatePayment].
  Future<SellerBanner> requestBanner({
    required String title,
    String subtitle = '',
    required int durationDays,
  }) async {
    final res = await _api.post(
      AppConstants.sellerBannerRequestEndpoint,
      data: {
        'title': title,
        'subtitle': subtitle,
        'duration_days': durationDays,
      },
    );
    return SellerBanner.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<SellerBanner>> myBanners() async {
    final res = await _api.get(AppConstants.sellerBannerListEndpoint);
    final data = res.data;
    if (data is List) {
      return data.map((e) => SellerBanner.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  /// Mobile-money-only. The provider is auto-detected from [payerNumber] on
  /// the server, so unlike order checkout there's no provider to pick here.
  Future<Map<String, dynamic>> initiatePayment({
    required int bannerId,
    required String payerNumber,
  }) async {
    final res = await _api.post(
      AppConstants.bannerPaymentInitiateEndpoint,
      data: {'banner_id': bannerId, 'payer_number': payerNumber},
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> checkPaymentStatus(int bannerId) async {
    final res = await _api.get(
      '${AppConstants.bannerPaymentStatusEndpoint}?banner_id=$bannerId',
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  static String errorMessage(Object e, {String fallback = 'Something went wrong. Please try again.'}) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['error'] is String) return data['error'] as String;
      if (data is Map && data['detail'] is String) return data['detail'] as String;
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Could not reach the server. Check your connection.';
      }
    }
    return fallback;
  }
}

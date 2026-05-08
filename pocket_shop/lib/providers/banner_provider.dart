import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/promo_banner.dart';
import '../services/api_service.dart';
import '../core/constants/app_constants.dart';

/// Fetches active promo banners from the backend.
/// Falls back to [PromoBanner.defaults] on any error so the home screen
/// always has content.
final bannerProvider = FutureProvider<List<PromoBanner>>((ref) async {
  try {
    final response = await ApiService().get(
      '${AppConstants.productsEndpoint}banners/',
    );
    final data = response.data;
    List rawList;
    if (data is Map<String, dynamic>) {
      // paginated or wrapped response
      rawList = (data['results'] as List?) ?? [];
    } else if (data is List) {
      rawList = data;
    } else {
      rawList = [];
    }

    if (rawList.isEmpty) {
      return PromoBanner.defaults;
    }

    return rawList
        .map((j) => PromoBanner.fromJson(j as Map<String, dynamic>))
        .toList();
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[BannerProvider] Failed to load banners: $e');
    }
    return PromoBanner.defaults;
  }
});

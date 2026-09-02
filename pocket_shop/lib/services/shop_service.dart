import 'package:dio/dio.dart';

import '../core/constants/app_constants.dart';
import '../models/shop.dart';
import 'api_service.dart';

class ShopQuery {
  ShopQuery({
    this.search,
    this.lat,
    this.lng,
    this.maxKm,
    this.page = 1,
    this.pageSize = 20,
  });

  final String? search;
  final double? lat;
  final double? lng;
  final double? maxKm;
  final int page;
  final int pageSize;
}

class ShopPage {
  ShopPage({
    required this.items,
    required this.nextPage,
    required this.totalCount,
  });

  final List<Shop> items;
  final int? nextPage;
  final int totalCount;
}

class ShopService {
  final ApiService _apiService = ApiService();

  Future<ShopPage> getShopsPage(ShopQuery query) async {
    final params = <String, dynamic>{
      'page': query.page,
      'page_size': query.pageSize,
      if (query.search != null && query.search!.trim().isNotEmpty)
        'search': query.search!.trim(),
      if (query.lat != null) 'lat': query.lat,
      if (query.lng != null) 'lng': query.lng,
      if (query.maxKm != null) 'max_km': query.maxKm,
    };
    try {
      final response = await _apiService.get(
        AppConstants.shopsEndpoint,
        queryParameters: params,
      );
      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final rawResults = data['results'];
        final results = rawResults is List
            ? rawResults
                .map((item) => Shop.fromJson(item as Map<String, dynamic>))
                .toList()
            : <Shop>[];
        final nextRaw = data['next']?.toString();
        final next = (nextRaw != null && nextRaw.isNotEmpty) ? query.page + 1 : null;
        return ShopPage(
          items: results,
          nextPage: next,
          totalCount: (data['count'] as int?) ?? results.length,
        );
      }
      return ShopPage(items: const [], nextPage: null, totalCount: 0);
    } on DioException catch (e) {
      throw Exception(_extractDioError(e));
    }
  }

  Future<Shop> getShop(int shopId) async {
    try {
      final response = await _apiService.get('${AppConstants.shopsEndpoint}$shopId/');
      return Shop.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(_extractDioError(e));
    }
  }

  String _extractDioError(DioException e) {
    if (e.response?.data is Map) {
      final data = e.response!.data as Map;
      final parts = <String>[];
      for (final entry in data.entries) {
        final key = entry.key.toString();
        final val = entry.value;
        if (val is List && val.isNotEmpty) {
          parts.add('$key: ${val.first}');
        } else {
          parts.add('$key: $val');
        }
      }
      if (parts.isNotEmpty) return parts.join('; ');
    }
    if (e.response?.data is String && (e.response!.data as String).isNotEmpty) {
      return e.response!.data as String;
    }
    return 'Request failed (${e.response?.statusCode ?? 'network error'})';
  }
}

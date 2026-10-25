import '../core/constants/app_constants.dart';
import '../models/shop_type.dart';
import 'api_service.dart';

class ShopTypeService {
  final ApiService _apiService = ApiService();

  Future<List<ShopType>> getShopTypes() async {
    try {
      final response = await _apiService.get(AppConstants.shopTypesEndpoint);
      final data = response.data;
      if (data is List) {
        return data.map((item) => ShopType.fromJson(item as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (e) {
      throw Exception('Failed to load shop types: $e');
    }
  }
}

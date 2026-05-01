import 'api_service.dart';
import '../models/category.dart';

class CategoryService {
  final ApiService _apiService = ApiService();

  Future<List<Category>> getCategories() async {
    try {
      final response = await _apiService.get('/products/categories/');
      if (response.data is Map && response.data['results'] is List) {
        return (response.data['results'] as List).map((item) => Category.fromJson(item)).toList();
      } else if (response.data is List) {
        return (response.data as List).map((item) => Category.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      throw Exception('Failed to load categories: $e');
    }
  }
}

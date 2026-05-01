import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/category.dart';
import '../services/category_service.dart';

final categoryServiceProvider = Provider<CategoryService>((ref) {
  return CategoryService();
});

final allCategoriesProvider = FutureProvider<List<Category>>((ref) async {
  final service = ref.read(categoryServiceProvider);
  return service.getCategories();
});

final categoryProvider = FutureProvider<List<Category>>((ref) async {
  final all = await ref.watch(allCategoriesProvider.future);
  // Only show top-level categories on the home screen
  return all.where((c) => c.parentId == null).toList();
});

final selectedCategoryProvider = StateProvider<int?>((ref) => null);

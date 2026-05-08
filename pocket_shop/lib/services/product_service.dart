import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/constants/app_constants.dart';
import '../models/product.dart';
import 'api_service.dart';

class ProductQuery {
  ProductQuery({
    this.search,
    this.category,
    this.inStockOnly = false,
    this.sortBy = 'default',
    this.page = 1,
    this.pageSize = 12,
  });

  final String? search;
  final String? category;
  final bool inStockOnly;
  final String sortBy;
  final int page;
  final int pageSize;
}

class ProductPage {
  ProductPage({
    required this.items,
    required this.nextPage,
    required this.totalCount,
  });

  final List<Product> items;
  final int? nextPage;
  final int totalCount;
}

/// One file for multipart field `images` (repeat up to 5 on the server).
class ProductImageUpload {
  ProductImageUpload({
    this.path,
    this.bytes,
    required this.filename,
  });

  final String? path;
  final Uint8List? bytes;
  final String filename;
}

class ProductService {
  final ApiService _apiService = ApiService();

  Future<ProductPage> getProductsPage(ProductQuery query) async {
    final ordering = switch (query.sortBy) {
      'price_low' => 'price',
      'price_high' => '-price',
      'name_az' => 'name',
      'latest' => '-created_at',
      _ => '-created_at',
    };
    final params = <String, dynamic>{
      'page': query.page,
      'page_size': query.pageSize,
      'ordering': ordering,
      if (query.search != null && query.search!.trim().isNotEmpty)
        'search': query.search!.trim(),
      if (query.category != null &&
          query.category!.trim().isNotEmpty &&
          query.category != 'all')
        'category': query.category,
      if (query.inStockOnly) 'in_stock': true,
    };
    try {
      final response = await _apiService.get(
        AppConstants.productsEndpoint,
        queryParameters: params,
      );
      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final rawResults = data['results'];
        final results = rawResults is List
            ? rawResults
                .map((item) => Product.fromJson(item as Map<String, dynamic>))
                .toList()
            : <Product>[];
        final nextRaw = data['next']?.toString();
        final next = (nextRaw != null && nextRaw.isNotEmpty)
            ? query.page + 1
            : null;
        return ProductPage(
          items: results,
          nextPage: next,
          totalCount: (data['count'] as int?) ?? results.length,
        );
      }
      if (response.data is List) {
        final rows = (response.data as List)
            .map((item) => Product.fromJson(item as Map<String, dynamic>))
            .toList();
        return ProductPage(items: rows, nextPage: null, totalCount: rows.length);
      }
      return ProductPage(items: const [], nextPage: null, totalCount: 0);
    } catch (e) {
      throw Exception('Failed to load products: $e');
    }
  }

  Future<List<Product>> getProducts({int? categoryId, String? search}) async {
    try {
      final Map<String, dynamic> queryParams = {};
      if (categoryId != null) queryParams['category'] = categoryId;
      if (search != null && search.isNotEmpty) queryParams['search'] = search;

      final response = await _apiService.get(
        AppConstants.productsEndpoint, 
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );
      
      if (response.data is List) {
        return (response.data as List).map((item) => Product.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      throw Exception('Failed to load products: $e');
    }
  }

  Future<List<Product>> getRecommendedProducts({String? category}) async {
    try {
      final params = <String, dynamic>{};
      if (category != null && category.isNotEmpty && category != 'all') {
        params['category'] = category;
      }
      final response = await _apiService.get(
        '${AppConstants.productsEndpoint}recommended/',
        queryParameters: params.isNotEmpty ? params : null,
      );
      if (response.data is List) {
        return (response.data as List).map((item) => Product.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      throw Exception('Failed to load recommended products: $e');
    }
  }

  Future<void> trackInteraction(int productId, String type) async {
    try {
      await _apiService.post('${AppConstants.productsEndpoint}interact/', data: {
        'product_id': productId,
        'interaction_type': type,
      });
    } catch (e) {
      // Fail silently for analytics
    }
  }

  Future<List<Product>> fetchTrending({int page = 1, int pageSize = 8, String? category}) async {
    final params = <String, dynamic>{'page': page, 'page_size': pageSize};
    if (category != null && category.isNotEmpty && category != 'all') {
      params['category'] = category;
    }
    final response = await _apiService.get(
      '${AppConstants.productsEndpoint}trending/',
      queryParameters: params,
    );
    if (response.data is Map<String, dynamic>) {
      final results = (response.data as Map<String, dynamic>)['results'];
      if (results is List) {
        return results
            .map((item) => Product.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    }
    return [];
  }

  Future<List<Product>> fetchRelated(int productId) async {
    final response =
        await _apiService.get('${AppConstants.productsEndpoint}$productId/related/');
    if (response.data is Map<String, dynamic>) {
      final results = (response.data as Map<String, dynamic>)['results'];
      if (results is List) {
        return results
            .map((item) => Product.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    }
    return [];
  }

  Future<Product> addProduct({
    required String name,
    required double price,
    required int stockQuantity,
    String description = '',
    String category = 'other',
    String quality = 'new',
    bool isAvailable = true,
    List<ProductImageUpload> images = const [],
    List<Map<String, dynamic>> variants = const [],
  }) async {
    try {
      if (images.isEmpty) {
        final response = await _apiService.post(
          AppConstants.productsEndpoint,
          data: {
            'name': name,
            'description': description,
            'price': price,
            'category': category,
            'quality': quality,
            'stock_quantity': stockQuantity,
            'is_available': isAvailable,
            'variant_payload': variants,
          },
        );
        return Product.fromJson(response.data as Map<String, dynamic>);
      }

      final form = FormData();
      form.fields.addAll([
        MapEntry('name', name),
        MapEntry('description', description),
        MapEntry('price', price.toString()),
        MapEntry('category', category),
        MapEntry('quality', quality),
        MapEntry('stock_quantity', stockQuantity.toString()),
        MapEntry('is_available', isAvailable ? 'true' : 'false'),
        if (variants.isNotEmpty)
          MapEntry('variant_payload', jsonEncode(variants)),
      ]);

      for (final img in images) {
        if (img.path != null && img.path!.isNotEmpty) {
          final p = img.path!;
          final nameFile = p.contains(Platform.pathSeparator)
              ? p.split(Platform.pathSeparator).last
              : p.split('/').last;
          final fname = nameFile.isNotEmpty ? nameFile : img.filename;
          form.files.add(
            MapEntry(
              'images',
              await MultipartFile.fromFile(
                p,
                filename: fname,
                contentType: DioMediaType.parse(_mimeFromFilename(fname)),
              ),
            ),
          );
        } else if (img.bytes != null && img.bytes!.isNotEmpty) {
          form.files.add(
            MapEntry(
              'images',
              MultipartFile.fromBytes(
                img.bytes!,
                filename: img.filename,
                contentType: DioMediaType.parse(_mimeFromFilename(img.filename)),
              ),
            ),
          );
        }
      }

      final response = await _apiService.post(
        AppConstants.productsEndpoint,
        data: form,
      );
      return Product.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(_extractDioError(e));
    } catch (e) {
      throw Exception('An unexpected error occurred: $e');
    }
  }

  Future<void> deleteProduct(int productId) async {
    try {
      await _apiService.delete('${AppConstants.productsEndpoint}$productId/');
    } on DioException catch (e) {
      throw Exception(_extractDioError(e));
    }
  }

  /// When [replacementImages] is non-null and not empty, sends multipart and replaces the gallery.
  Future<Product> updateProduct({
    required int productId,
    required Map<String, dynamic> data,
    List<ProductImageUpload>? replacementImages,
    List<Map<String, dynamic>>? variants,
  }) async {
    try {
      if (replacementImages != null && replacementImages.isNotEmpty) {
        final form = FormData();
        for (final e in data.entries) {
          form.fields.add(MapEntry(e.key, e.value.toString()));
        }
        if (variants != null) {
          form.fields.add(MapEntry('variant_payload', jsonEncode(variants)));
        }
        for (final img in replacementImages) {
          if (img.path != null && img.path!.isNotEmpty) {
            final p = img.path!;
            final nameFile = p.contains(Platform.pathSeparator)
                ? p.split(Platform.pathSeparator).last
                : p.split('/').last;
            final fname = nameFile.isNotEmpty ? nameFile : img.filename;
            form.files.add(
              MapEntry(
                'images',
                await MultipartFile.fromFile(
                  p,
                  filename: fname,
                  contentType: DioMediaType.parse(_mimeFromFilename(fname)),
                ),
              ),
            );
          } else if (img.bytes != null && img.bytes!.isNotEmpty) {
            form.files.add(
              MapEntry(
                'images',
                MultipartFile.fromBytes(
                  img.bytes!,
                  filename: img.filename,
                  contentType: DioMediaType.parse(_mimeFromFilename(img.filename)),
                ),
              ),
            );
          }
        }
        final response = await _apiService.put(
          '${AppConstants.productsEndpoint}$productId/',
          data: form,
        );
        return Product.fromJson(response.data as Map<String, dynamic>);
      }

      final response = await _apiService.put(
        '${AppConstants.productsEndpoint}$productId/',
        data: {
          ...data,
          if (variants != null) 'variant_payload': variants,
        },
      );
      return Product.fromJson(response.data as Map<String, dynamic>);
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

  static String _mimeFromFilename(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_shop/models/product.dart';

void main() {
  test('Product.fromJson parses review and variants', () {
    final product = Product.fromJson({
      'id': 1,
      'name': 'Phone',
      'description': 'A phone',
      'price': '99.50',
      'category': 'electronics',
      'quality': 'new',
      'seller': 2,
      'stock_quantity': 4,
      'is_available': true,
      'is_in_stock': true,
      'review_avg': 4.2,
      'review_count': 7,
      'variants': [
        {
          'id': 9,
          'name': 'Color',
          'value': 'Black',
          'sku': 'BLK-1',
          'stock_quantity': 2,
        },
      ],
      'created_at': DateTime.now().toIso8601String(),
      'images': const [],
    });

    expect(product.reviewAverage, 4.2);
    expect(product.reviewCount, 7);
    expect(product.variants.length, 1);
    expect(product.variants.first.sku, 'BLK-1');
  });
}

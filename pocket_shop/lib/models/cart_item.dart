import 'product.dart';

class CartItem {
  /// Server `CartItem.id`; null when only local/offline.
  final int? cartItemId;
  final Product product;
  final int quantity;

  CartItem({
    this.cartItemId,
    required this.product,
    this.quantity = 1,
  });

  CartItem copyWith({int? cartItemId, Product? product, int? quantity}) {
    return CartItem(
      cartItemId: cartItemId ?? this.cartItemId,
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
    );
  }

  double get subtotal => product.price * quantity;

  Map<String, dynamic> toJson() {
    return {
      'product': product.toJson(),
      'quantity': quantity,
    };
  }
}

/// What kind of store a shop is (Supermarket, Pharmacy, Electronics
/// Store...). Staff-assigned in the admin, not derived from products —
/// mirrors accounts.ShopType.
class ShopType {
  final int id;
  final String name;
  final String iconName;

  const ShopType({required this.id, required this.name, this.iconName = ''});

  factory ShopType.fromJson(Map<String, dynamic> json) {
    return ShopType(
      id: json['id'] as int,
      name: json['name']?.toString() ?? '',
      iconName: json['icon_name']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'icon_name': iconName};
}

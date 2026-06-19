class Category {
  final int id;
  final String name;
  final String slug;
  final String? iconName;
  final int? parentId;

  Category({
    required this.id,
    required this.name,
    required this.slug,
    this.iconName,
    this.parentId,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'],
      name: json['name'],
      slug: json['slug'],
      iconName: json['icon_name'],
      parentId: json['parent'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'slug': slug,
    'icon_name': iconName,
    'parent': parentId,
  };
}

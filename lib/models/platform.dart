class Platform {
  final String id;
  final String brand;
  final String name;

  const Platform({required this.id, required this.brand, required this.name});

  factory Platform.fromJson(Map<String, dynamic> json) {
    return Platform(
      id: json['id'] as String,
      brand: json['brand'] as String,
      name: json['name'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'brand': brand, 'name': name};
  }

  @override
  String toString() => '$brand - $name';
}

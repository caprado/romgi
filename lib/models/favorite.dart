class Favorite {
  final String slug;
  final String title;
  final String platform;
  final String? boxartUrl;
  final DateTime addedAt;

  const Favorite({
    required this.slug,
    required this.title,
    required this.platform,
    this.boxartUrl,
    required this.addedAt,
  });

  factory Favorite.fromMap(Map<String, dynamic> map) {
    return Favorite(
      slug: map['slug'] as String,
      title: map['title'] as String,
      platform: map['platform'] as String,
      boxartUrl: map['boxart_url'] as String?,
      addedAt: DateTime.fromMillisecondsSinceEpoch(map['added_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'slug': slug,
      'title': title,
      'platform': platform,
      'boxart_url': boxartUrl,
      'added_at': addedAt.millisecondsSinceEpoch,
    };
  }
}

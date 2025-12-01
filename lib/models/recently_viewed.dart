class RecentlyViewed {
  final String slug;
  final String title;
  final String platform;
  final String? boxartUrl;
  final DateTime viewedAt;

  const RecentlyViewed({
    required this.slug,
    required this.title,
    required this.platform,
    this.boxartUrl,
    required this.viewedAt,
  });

  factory RecentlyViewed.fromMap(Map<String, dynamic> map) {
    return RecentlyViewed(
      slug: map['slug'] as String,
      title: map['title'] as String,
      platform: map['platform'] as String,
      boxartUrl: map['boxart_url'] as String?,
      viewedAt: DateTime.fromMillisecondsSinceEpoch(map['viewed_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'slug': slug,
      'title': title,
      'platform': platform,
      'boxart_url': boxartUrl,
      'viewed_at': viewedAt.millisecondsSinceEpoch,
    };
  }
}

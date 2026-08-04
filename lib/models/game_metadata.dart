class GameMetadata {
  final String? description;
  final List<String> screenshotUrls;
  final List<String> artworkUrls;

  const GameMetadata({
    this.description,
    this.screenshotUrls = const [],
    this.artworkUrls = const [],
  });

  bool get isEmpty =>
      (description == null || description!.isEmpty) &&
      screenshotUrls.isEmpty &&
      artworkUrls.isEmpty;

  factory GameMetadata.fromJson(Map<String, dynamic> json) {
    return GameMetadata(
      description: json['description'] as String?,
      screenshotUrls:
          (json['screenshots'] as List<dynamic>?)?.whereType<String>().toList() ??
              const [],
      artworkUrls:
          (json['artwork'] as List<dynamic>?)?.whereType<String>().toList() ??
              const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'description': description,
      'screenshots': screenshotUrls,
      'artwork': artworkUrls,
    };
  }
}

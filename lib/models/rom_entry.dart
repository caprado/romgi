import 'download_link.dart';

class RomEntry {
  final String slug;
  final String? romId;
  final String title;
  final String platform;
  final String? boxartUrl;
  final List<String> regions;
  final List<DownloadLink> links;

  const RomEntry({
    required this.slug,
    this.romId,
    required this.title,
    required this.platform,
    this.boxartUrl,
    required this.regions,
    required this.links,
  });

  factory RomEntry.fromJson(Map<String, dynamic> json) {
    return RomEntry(
      slug: json['slug'] as String,
      romId: json['rom_id'] as String?,
      title: json['title'] as String,
      platform: json['platform'] as String,
      boxartUrl: json['boxart_url'] as String?,
      regions: (json['regions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      links: (json['links'] as List<dynamic>?)
              ?.map((e) => DownloadLink.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'slug': slug,
      'rom_id': romId,
      'title': title,
      'platform': platform,
      'boxart': boxartUrl,
      'regions': regions,
      'links': links.map((e) => e.toJson()).toList(),
    };
  }
}

class SearchResult {
  final List<RomEntry> entries;
  final int totalResults;
  final int currentPage;
  final int totalPages;
  final int currentResults;

  const SearchResult({
    required this.entries,
    required this.totalResults,
    required this.currentPage,
    required this.totalPages,
    required this.currentResults,
  });

  bool get hasMore => currentPage < totalPages;

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      entries: (json['results'] as List<dynamic>?)
              ?.map((e) => RomEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      totalResults: json['total_results'] as int? ?? 0,
      currentPage: json['current_page'] as int? ?? 1,
      totalPages: json['total_pages'] as int? ?? 1,
      currentResults: json['current_results'] as int? ?? 0,
    );
  }
}

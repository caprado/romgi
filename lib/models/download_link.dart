class DownloadLink {
  final String name;
  final String type;
  final String format;
  final String url;
  final String filename;
  final String host;
  final int size;
  final String sizeStr;
  final String sourceUrl;
  final String? sourceId;
  final bool requiresAuth;
  final String? torrentInfohash;
  final int? torrentFileIndex;
  final String? torrentFilePath;

  /// Debrid-resolved CDN link; torrent fields are kept so an expired URL
  /// can be re-resolved.
  final bool debridResolved;

  const DownloadLink({
    required this.name,
    required this.type,
    required this.format,
    required this.url,
    required this.filename,
    required this.host,
    required this.size,
    required this.sizeStr,
    required this.sourceUrl,
    this.sourceId,
    this.requiresAuth = false,
    this.torrentInfohash,
    this.torrentFileIndex,
    this.torrentFilePath,
    this.debridResolved = false,
  });

  bool get isTorrent => torrentInfohash != null && !debridResolved;

  DownloadLink copyWith({
    String? name,
    String? type,
    String? format,
    String? url,
    String? filename,
    String? host,
    int? size,
    String? sizeStr,
    String? sourceUrl,
    String? sourceId,
    bool? requiresAuth,
    bool? debridResolved,
  }) {
    return DownloadLink(
      name: name ?? this.name,
      type: type ?? this.type,
      format: format ?? this.format,
      url: url ?? this.url,
      filename: filename ?? this.filename,
      host: host ?? this.host,
      size: size ?? this.size,
      sizeStr: sizeStr ?? this.sizeStr,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      sourceId: sourceId ?? this.sourceId,
      requiresAuth: requiresAuth ?? this.requiresAuth,
      torrentInfohash: torrentInfohash,
      torrentFileIndex: torrentFileIndex,
      torrentFilePath: torrentFilePath,
      debridResolved: debridResolved ?? this.debridResolved,
    );
  }

  factory DownloadLink.fromJson(Map<String, dynamic> json) {
    return DownloadLink(
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'Game',
      format: json['format'] as String? ?? '',
      url: json['url'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      host: json['host'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      sizeStr: json['size_str'] as String? ?? '',
      sourceUrl: json['source_url'] as String? ?? '',
      sourceId: json['source_id'] as String?,
      requiresAuth: (json['requires_auth'] as int? ?? 0) != 0,
      torrentInfohash: json['torrent_infohash'] as String?,
      torrentFileIndex: json['torrent_file_index'] as int?,
      torrentFilePath: json['torrent_file_path'] as String?,
      debridResolved: (json['debrid_resolved'] as int? ?? 0) != 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type,
      'format': format,
      'url': url,
      'filename': filename,
      'host': host,
      'size': size,
      'size_str': sizeStr,
      'source_url': sourceUrl,
      if (sourceId != null) 'source_id': sourceId,
      'requires_auth': requiresAuth ? 1 : 0,
      if (torrentInfohash != null) 'torrent_infohash': torrentInfohash,
      if (torrentFileIndex != null) 'torrent_file_index': torrentFileIndex,
      if (torrentFilePath != null) 'torrent_file_path': torrentFilePath,
      if (debridResolved) 'debrid_resolved': 1,
    };
  }
}

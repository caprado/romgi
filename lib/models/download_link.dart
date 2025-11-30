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
  });

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
    };
  }
}

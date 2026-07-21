import 'dart:convert';

class TorrentMetadata {
  final String infohash;
  final String? magnet;
  final List<String> trackers;
  final String? name;
  final int? totalSize;
  final int? fileCount;

  const TorrentMetadata({
    required this.infohash,
    this.magnet,
    this.trackers = const [],
    this.name,
    this.totalSize,
    this.fileCount,
  });

  factory TorrentMetadata.fromRow(Map<String, Object?> row) {
    final trackersRaw = row['trackers_json'] as String?;
    var trackers = const <String>[];
    if (trackersRaw != null && trackersRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(trackersRaw);
        if (decoded is List) {
          trackers = decoded.whereType<String>().toList();
        }
      } catch (_) {
        // Malformed tracker JSON → treat as no trackers.
      }
    }

    return TorrentMetadata(
      infohash: row['infohash'] as String,
      magnet: row['magnet'] as String?,
      trackers: trackers,
      name: row['name'] as String?,
      totalSize: row['total_size'] as int?,
      fileCount: row['file_count'] as int?,
    );
  }
}

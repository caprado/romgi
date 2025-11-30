import 'download_link.dart';

enum DownloadStatus {
  pending,
  downloading,
  paused,
  extracting,
  completed,
  failed,
}

class DownloadTask {
  final String id;
  final String slug;
  final String title;
  final String platform;
  final String? boxartUrl;
  final DownloadLink link;
  final DownloadStatus status;
  final double progress;
  final int downloadedBytes;
  final int totalBytes;
  final int bytesPerSecond; // Download speed in bytes/second
  final String? filePath;
  final String? error;
  final DateTime createdAt;
  final DateTime? completedAt;
  final bool hiddenFromHistory;

  const DownloadTask({
    required this.id,
    required this.slug,
    required this.title,
    required this.platform,
    this.boxartUrl,
    required this.link,
    this.status = DownloadStatus.pending,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.bytesPerSecond = 0,
    this.filePath,
    this.error,
    required this.createdAt,
    this.completedAt,
    this.hiddenFromHistory = false,
  });

  DownloadTask copyWith({
    DownloadStatus? status,
    double? progress,
    int? downloadedBytes,
    int? totalBytes,
    int? bytesPerSecond,
    String? filePath,
    String? error,
    DateTime? completedAt,
    bool? hiddenFromHistory,
  }) {
    return DownloadTask(
      id: id,
      slug: slug,
      title: title,
      platform: platform,
      boxartUrl: boxartUrl,
      link: link,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
      filePath: filePath ?? this.filePath,
      error: error,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
      hiddenFromHistory: hiddenFromHistory ?? this.hiddenFromHistory,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'slug': slug,
      'title': title,
      'platform': platform,
      'boxart_url': boxartUrl,
      'link_name': link.name,
      'link_type': link.type,
      'link_format': link.format,
      'link_url': link.url,
      'link_filename': link.filename,
      'link_host': link.host,
      'link_size': link.size,
      'link_size_str': link.sizeStr,
      'link_source_url': link.sourceUrl,
      'status': status.index,
      'progress': progress,
      'downloaded_bytes': downloadedBytes,
      'total_bytes': totalBytes,
      'file_path': filePath,
      'error': error,
      'created_at': createdAt.millisecondsSinceEpoch,
      'completed_at': completedAt?.millisecondsSinceEpoch,
      'hidden_from_history': hiddenFromHistory ? 1 : 0,
    };
  }

  factory DownloadTask.fromMap(Map<String, dynamic> map) {
    return DownloadTask(
      id: map['id'] as String,
      slug: map['slug'] as String,
      title: map['title'] as String,
      platform: map['platform'] as String,
      boxartUrl: map['boxart_url'] as String?,
      link: DownloadLink(
        name: map['link_name'] as String,
        type: map['link_type'] as String,
        format: map['link_format'] as String,
        url: map['link_url'] as String,
        filename: map['link_filename'] as String,
        host: map['link_host'] as String,
        size: map['link_size'] as int,
        sizeStr: map['link_size_str'] as String,
        sourceUrl: map['link_source_url'] as String,
      ),
      status: DownloadStatus.values[map['status'] as int],
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      downloadedBytes: (map['downloaded_bytes'] as int?) ?? 0,
      totalBytes: (map['total_bytes'] as int?) ?? 0,
      filePath: map['file_path'] as String?,
      error: map['error'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      completedAt: map['completed_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['completed_at'] as int)
          : null,
      hiddenFromHistory: (map['hidden_from_history'] as int? ?? 0) == 1,
    );
  }

  String get statusText {
    switch (status) {
      case DownloadStatus.pending:
        return 'Waiting...';
      case DownloadStatus.downloading:
        return 'Downloading...';
      case DownloadStatus.paused:
        return 'Paused';
      case DownloadStatus.extracting:
        return 'Extracting...';
      case DownloadStatus.completed:
        return 'Completed';
      case DownloadStatus.failed:
        return 'Failed';
    }
  }

  String get progressText {
    if (totalBytes > 0) {
      final downloadedMB = downloadedBytes / (1024 * 1024);
      final totalMB = totalBytes / (1024 * 1024);
      return '${downloadedMB.toStringAsFixed(1)} / ${totalMB.toStringAsFixed(1)} MB';
    }
    return link.sizeStr;
  }

  String get speedText {
    if (bytesPerSecond <= 0) return '';
    if (bytesPerSecond < 1024) {
      return '$bytesPerSecond B/s';
    } else if (bytesPerSecond < 1024 * 1024) {
      final kbps = bytesPerSecond / 1024;
      return '${kbps.toStringAsFixed(1)} KB/s';
    } else {
      final mbps = bytesPerSecond / (1024 * 1024);
      return '${mbps.toStringAsFixed(1)} MB/s';
    }
  }
}

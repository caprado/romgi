// Pigeon spec for the Dart↔Kotlin torrent bridge.
// Regenerate: dart run pigeon --input pigeons/torrent_api.dart

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/torrent/torrent_api.g.dart',
  dartOptions: DartOptions(),
  kotlinOut:
      'android/app/src/main/kotlin/com/caprado/romgi/torrent/TorrentApi.g.kt',
  kotlinOptions: KotlinOptions(package: 'com.caprado.romgi.torrent'),
  dartPackageName: 'romgi',
))

/// One file inside a torrent.
class TorrentFile {
  TorrentFile({
    required this.index,
    required this.path,
    required this.length,
    required this.bytesDownloaded,
    required this.priority,
  });

  /// Position in the torrent's file list. Stable across sessions.
  int index;

  /// Path inside the torrent (forward slashes, no leading slash).
  String path;

  /// Total file size in bytes.
  int length;

  /// How much of this file is on disk.
  int bytesDownloaded;

  /// libtorrent priority. 0 = don't download, 1..7 = increasing.
  int priority;
}

/// Live state of a single torrent. Streamed via [TorrentEvents].
class TorrentProgress {
  TorrentProgress({
    required this.infohash,
    required this.name,
    required this.state,
    required this.totalSize,
    required this.bytesDownloaded,
    required this.downloadRate,
    required this.uploadRate,
    required this.peers,
    required this.seeds,
    required this.error,
    required this.files,
  });

  String infohash;
  String name;

  /// One of: queued, checking_files, downloading_metadata, downloading,
  /// finished, seeding, allocating, paused, error, unknown.
  String state;
  int totalSize;
  int bytesDownloaded;

  /// Bytes/sec.
  int downloadRate;
  int uploadRate;
  int peers;
  int seeds;

  /// Empty when no error.
  String error;

  /// Per-file progress. Snapshot at the moment of emission.
  List<TorrentFile> files;
}

/// Configuration for the torrent session.
class TorrentSettings {
  TorrentSettings({
    required this.savePath,
    required this.seedingEnabled,
    required this.dhtEnabled,
    required this.maxConnections,
    required this.maxUploads,
    required this.maxDownloadRateBytesPerSec,
    required this.maxUploadRateBytesPerSec,
  });

  /// Where torrent payloads are written. App-private; the
  /// TorrentAdapter moves completed files into the per-platform Roms folder.
  String savePath;

  /// When false, the session stops uploading the moment a torrent
  /// completes. Default true.
  bool seedingEnabled;

  /// DHT for trackerless peer discovery. Default true.
  bool dhtEnabled;

  int maxConnections;
  int maxUploads;
  int maxDownloadRateBytesPerSec; // 0 = unlimited
  int maxUploadRateBytesPerSec; // 0 = unlimited
}

/// Request to add a torrent. At least one of [magnet]/[torrentBytes]
/// must be set; [magnet] wins when both are present.
class AddTorrentRequest {
  AddTorrentRequest({
    required this.magnet,
    required this.torrentBytes,
    required this.fileIndices,
  });

  String? magnet;

  /// Raw .torrent bytes. Honored when [magnet] is null.
  Uint8List? torrentBytes;

  /// File indices to download. Every other file's priority is set to 0.
  /// An empty list means "download all".
  List<int> fileIndices;
}

/// Methods Dart calls into Kotlin.
@HostApi()
abstract class TorrentHostApi {
  /// Idempotent. Called from app bootstrap before any other method.
  void start(TorrentSettings settings);

  void updateSettings(TorrentSettings settings);

  /// Adds the torrent and returns its infohash. If the torrent is already
  /// in the session, file priorities are *unioned* with [request.fileIndices]
  /// — a previously-zero file gets pulled in without losing existing ones.
  String addTorrent(AddTorrentRequest request);

  void cancel(String infohash);

  void pauseAll();
  void resumeAll();

  /// One-shot snapshot. Useful for UI on cold start; ongoing updates
  /// arrive via [TorrentEvents.onProgress].
  List<TorrentProgress> listAll();
}

/// Methods Kotlin calls into Dart. Push-style updates from the runtime.
@FlutterApi()
abstract class TorrentEvents {
  void onProgress(TorrentProgress progress);
  void onError(String infohash, String error);
}

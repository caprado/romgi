import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:romgi/models/models.dart';
import 'package:romgi/services/database_service.dart';
import 'package:romgi/services/download_service.dart';
import 'package:romgi/services/host_adapter.dart';
import 'package:romgi/services/notification_service.dart';
import 'package:romgi/services/rom_database_service.dart';
import 'package:romgi/services/seven_zip_service.dart';
import 'package:romgi/services/storage_service.dart';
import 'package:romgi/services/torrent_info.dart';
import 'package:romgi/services/torrent_service.dart';
import 'package:romgi/torrent/torrent_api.g.dart';

import 'debrid/debrid_test_utils.dart';

const _hash = 'aabbccddeeff00112233445566778899aabbccdd';

class FakeDatabaseService extends Fake implements DatabaseService {
  final Map<String, DownloadTask> rows = {};
  bool servePendingQueue = false;

  @override
  Future<void> insertDownload(DownloadTask task) async {
    rows[task.id] = task;
  }

  @override
  Future<void> updateDownload(DownloadTask task) async {
    rows[task.id] = task;
  }

  @override
  Future<DownloadTask?> getDownload(String id) async => rows[id];

  @override
  Future<List<DownloadTask>> getDownloadsByGroup(String groupId) async => [];

  @override
  Future<List<DownloadTask>> getDownloadsByStatus(DownloadStatus status) async {
    if (!servePendingQueue && status == DownloadStatus.pending) return [];
    return rows.values.where((t) => t.status == status).toList();
  }
}

class FakeStorageService extends Fake implements StorageService {
  FakeStorageService(this.platformDir);

  final Directory platformDir;

  @override
  Future<Directory> getPlatformDirectory(String platform) async => platformDir;

  @override
  Future<String> getDownloadPath(String platform, String filename) async =>
      p.join(platformDir.path, filename);
}

class FakeNotificationService extends Fake implements NotificationService {
  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<void> cancelProgressNotification() async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> updateForTask(DownloadTask task) async {}

  @override
  Future<void> showDownloadProgress({
    required String title,
    required double progress,
    required String progressText,
  }) async {}
}

class FakeRomDatabaseService extends Fake implements RomDatabaseService {
  @override
  Future<RomEntry?> getEntry(String slug) async => null;

  @override
  Future<TorrentMetadata?> getTorrentMetadata(String infohash) async => null;
}

class RecordingTorrentService extends Fake implements TorrentService {
  final progress = StreamController<TorrentProgress>.broadcast();
  final errors =
      StreamController<({String infohash, String error})>.broadcast();
  final added =
      <({String? magnet, List<int>? torrentBytes, List<int> fileIndices})>[];

  @override
  Stream<TorrentProgress> get progressStream => progress.stream;

  @override
  Stream<({String infohash, String error})> get errorStream => errors.stream;

  @override
  Future<void> start({required bool seedingEnabled}) async {}

  @override
  Future<String> addTorrent({
    String? magnet,
    List<int>? torrentBytes,
    List<int> fileIndices = const [],
  }) async {
    added.add(
        (magnet: magnet, torrentBytes: torrentBytes, fileIndices: fileIndices));
    return _hash;
  }

  @override
  Future<void> cancel(String infohash) async {}
}

class FakeSevenZipService extends Fake implements SevenZipService {
  Future<String> Function(String archivePath, String outputDir)? onExtract;

  @override
  Future<String> extract(String archivePath, String outputDir) {
    final handler = onExtract;
    if (handler == null) throw Exception('boom');
    return handler(archivePath, outputDir);
  }
}

DownloadLink _httpLink(String filename, {required int size}) => DownloadLink(
      name: 'rom',
      type: 'Game',
      format: 'chd',
      url: 'https://host/$filename',
      filename: filename,
      host: 'host',
      size: size,
      sizeStr: '$size B',
      sourceUrl: 'https://host/',
      sourceId: 'host',
    );

DownloadLink _torrentLink(
  String filename, {
  required int size,
  int fileIndex = 0,
  String url = 'https://archive.org/download/item/file',
}) =>
    DownloadLink(
      name: 'rom',
      type: 'Game',
      format: 'chd',
      url: url,
      filename: filename,
      host: 'MiNERVA Archive',
      size: size,
      sizeStr: '$size B',
      sourceUrl: 'https://host/',
      sourceId: 'minerva',
      torrentInfohash: _hash,
      torrentFileIndex: fileIndex,
      torrentFilePath: filename,
    );

DownloadTask _task(String id, DownloadLink link,
        {DownloadStatus status = DownloadStatus.pending}) =>
    DownloadTask(
      id: id,
      slug: id,
      title: id,
      platform: 'psx',
      link: link,
      status: status,
      createdAt: DateTime(2026),
    );

TorrentFile _tFile(int index, String path, int length, int done) =>
    TorrentFile(
      index: index,
      path: path,
      length: length,
      bytesDownloaded: done,
      priority: 1,
    );

TorrentProgress _tProgress(List<TorrentFile> files) => TorrentProgress(
      infohash: _hash,
      name: 'item',
      state: 'downloading',
      totalSize: 0,
      bytesDownloaded: 0,
      downloadRate: 0,
      uploadRate: 0,
      peers: 1,
      seeds: 1,
      error: '',
      files: files,
    );

String _multiFileTorrent(List<(String, int)> files) {
  final buf = StringBuffer('d4:infod5:filesl');
  for (final (path, length) in files) {
    buf.write('d6:lengthi${length}e4:pathl${path.length}:${path}ee');
  }
  buf.write('e4:name4:iteme');
  buf.write('e');
  return buf.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory platformDir;
  late Directory torrentDir;
  late FakeDatabaseService db;
  late RecordingTorrentService torrents;
  late FakeSevenZipService sevenZip;
  late StubAdapter http;
  late DownloadService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('romgi_integrity_test');
    platformDir = Directory(p.join(tempDir.path, 'roms'))..createSync();
    torrentDir = Directory(p.join(tempDir.path, 'support', 'torrents'))
      ..createSync(recursive: true);
    db = FakeDatabaseService();
    torrents = RecordingTorrentService();
    sevenZip = FakeSevenZipService();
    http = StubAdapter({});
    service = DownloadService(
      db: db,
      romDb: FakeRomDatabaseService(),
      storage: FakeStorageService(platformDir),
      notifications: FakeNotificationService(),
      adapters: HostAdapterRegistry(),
      torrents: torrents,
      sevenZip: sevenZip,
      dio: Dio(BaseOptions(baseUrl: 'https://host'))..httpClientAdapter = http,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_foreground_task/methods'),
      (call) async {
        switch (call.method) {
          case 'isRunningService':
            return false;
          case 'isIgnoringBatteryOptimizations':
            return true;
          case 'startService':
          case 'stopService':
            return true;
          default:
            return null;
        }
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationSupportDirectory') {
          return p.join(tempDir.path, 'support');
        }
        return tempDir.path;
      },
    );
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_foreground_task/methods'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    torrents.progress.close();
    torrents.errors.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 250 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<DownloadTask> run(DownloadTask task,
      {bool Function(DownloadTask)? until}) async {
    db.rows[task.id] = task;
    db.servePendingQueue = true;
    final done = service.downloadStream
        .firstWhere(until ??
            (t) =>
                t.id == task.id &&
                (t.status == DownloadStatus.completed ||
                    t.status == DownloadStatus.failed))
        .timeout(const Duration(seconds: 5));
    service.setMaxConcurrentDownloads(1);
    return done;
  }

  File platformFile(String name, [int size = 0]) {
    final file = File(p.join(platformDir.path, name));
    file.writeAsBytesSync(List.filled(size, 0x61));
    return file;
  }

  File torrentFile(String name, [int size = 0]) {
    final file = File(p.join(torrentDir.path, name));
    file.writeAsBytesSync(List.filled(size, 0x61));
    return file;
  }

  group('http resume integrity', () {
    test('fully downloaded file completes without touching the network',
        () async {
      platformFile('Game.chd', 1000);
      final task = _task('t1', _httpLink('Game.chd', size: 1000));

      final result = await run(task);

      expect(result.status, DownloadStatus.completed);
      expect(result.filePath, p.join(platformDir.path, 'Game.chd'));
      expect(File(result.filePath!).lengthSync(), 1000);
      expect(http.calls, isEmpty);
    });

    test('fully downloaded archive extracts and completes without re-download',
        () async {
      platformFile('Game.zip', 1000);
      sevenZip.onExtract = (archive, outDir) async {
        File(p.join(outDir, 'Game.chd')).writeAsBytesSync(List.filled(5, 1));
        return p.join(outDir, 'Game.chd');
      };
      final task = _task('t1', _httpLink('Game.zip', size: 1000));

      final result = await run(task);

      expect(result.status, DownloadStatus.completed);
      expect(result.filePath, p.join(platformDir.path, 'Game.chd'));
      expect(File(result.filePath!).existsSync(), isTrue);
      expect(File(p.join(platformDir.path, 'Game.zip')).existsSync(), isFalse);
      expect(http.calls, isEmpty);
      expect(
        platformDir
            .listSync()
            .where((e) => p.basename(e.path).startsWith('.extract-')),
        isEmpty,
      );
    });

    test('oversized partial is deleted and the download restarts', () async {
      platformFile('Game.chd', 1500);
      http.routes['*'] = (_) => ResponseBody.fromString('nope', 404);
      final task = _task('t1', _httpLink('Game.chd', size: 1000));

      final result = await run(task);

      expect(result.status, DownloadStatus.failed);
      expect(http.calls, isNotEmpty);
      final file = File(p.join(platformDir.path, 'Game.chd'));
      expect(!file.existsSync() || file.lengthSync() != 1500, isTrue);
    });

    test('body shorter than Content-Length fails instead of completing',
        () async {
      http.routes['*'] = (_) => ResponseBody.fromString(
            'nope',
            200,
            headers: {
              Headers.contentLengthHeader: ['1000'],
            },
          );
      final task = _task('t1', _httpLink('Game.chd', size: 1000));

      final result = await run(task);

      expect(result.status, DownloadStatus.failed);
      expect(result.error, contains('incomplete'));
      expect(File(p.join(platformDir.path, 'Game.chd')).existsSync(), isFalse);
    });

    test('approximate catalog size completes when Content-Length matches',
        () async {
      http.routes['*'] = (_) => ResponseBody.fromString(
            'nope',
            200,
            headers: {
              Headers.contentLengthHeader: ['4'],
            },
          );
      final task = _task('t1', _httpLink('Game.chd', size: 1000));

      final result = await run(task);

      expect(result.status, DownloadStatus.completed);
      expect(File(p.join(platformDir.path, 'Game.chd')).lengthSync(), 4);
    });

    test('extraction failure fails the task and keeps the archive', () async {
      platformFile('Game.zip', 1000);
      sevenZip.onExtract = null;
      final task = _task('t1', _httpLink('Game.zip', size: 1000));

      final result = await run(task);

      expect(result.status, DownloadStatus.failed);
      expect(result.error, contains('Extraction failed'));
      expect(File(p.join(platformDir.path, 'Game.zip')).lengthSync(), 1000);
      expect(
        platformDir
            .listSync()
            .where((e) => p.basename(e.path).startsWith('.extract-')),
        isEmpty,
      );
    });

    test('task stuck in extracting completes from disk after re-queue',
        () async {
      platformFile('Game.zip', 1000);
      sevenZip.onExtract = (archive, outDir) async {
        File(p.join(outDir, 'Game.chd')).writeAsBytesSync(List.filled(5, 1));
        return p.join(outDir, 'Game.chd');
      };
      final stuck = _task('t1', _httpLink('Game.zip', size: 1000),
          status: DownloadStatus.extracting);
      db.rows[stuck.id] = stuck;

      final result = await run(
          stuck.copyWith(status: DownloadStatus.pending));

      expect(result.status, DownloadStatus.completed);
      expect(http.calls, isEmpty);
    });
  });

  group('torrent finish integrity', () {
    test('wrong file delivered fails instead of saving wrong content',
        () async {
      torrentFile('other.chd', 500);
      final task = _task('t1', _torrentLink('Game.chd', size: 500));

      final resultFuture = run(task);
      await waitFor(() => torrents.added.isNotEmpty);
      torrents.progress.add(_tProgress([_tFile(0, 'other.chd', 500, 500)]));
      final result = await resultFuture;

      expect(result.status, DownloadStatus.failed);
      expect(result.error, contains('instead of'));
      expect(File(p.join(platformDir.path, 'Game.chd')).existsSync(), isFalse);
    });

    test('short copy fails instead of completing with truncated data',
        () async {
      torrentFile('Game.chd', 500);
      final task = _task('t1', _torrentLink('Game.chd', size: 1000));

      final resultFuture = run(task);
      await waitFor(() => torrents.added.isNotEmpty);
      torrents.progress.add(_tProgress([_tFile(0, 'Game.chd', 1000, 1000)]));
      final result = await resultFuture;

      expect(result.status, DownloadStatus.failed);
      expect(result.error, contains('incomplete'));
      expect(File(p.join(platformDir.path, 'Game.chd')).existsSync(), isFalse);
    });

    test('matching file and size completes', () async {
      torrentFile('Game.chd', 1000);
      final task = _task('t1', _torrentLink('Game.chd', size: 1000));

      final resultFuture = run(task);
      await waitFor(() => torrents.added.isNotEmpty);
      torrents.progress.add(_tProgress([_tFile(0, 'Game.chd', 1000, 1000)]));
      final result = await resultFuture;

      expect(result.status, DownloadStatus.completed);
      expect(File(p.join(platformDir.path, 'Game.chd')).lengthSync(), 1000);
    });

    test('zero-byte leftover is not blessed as an extracted rom', () async {
      platformFile('Game.chd', 0);
      final task = _task('t1', _torrentLink('Game.zip', size: 1000));

      final resultFuture = run(
        task,
        until: (t) =>
            t.id == task.id &&
            (t.status == DownloadStatus.downloading ||
                t.status == DownloadStatus.failed),
      );
      await resultFuture;
      await waitFor(() => torrents.added.isNotEmpty);

      expect(torrents.added, isNotEmpty);
    });
  });

  group('torrent index reconciliation', () {
    test('stale index is remapped by filename from the fetched torrent',
        () async {
      http.routes['*'] = (_) => ResponseBody.fromString(
            _multiFileTorrent([('Game.chd', 1000), ('other.chd', 20)]),
            200,
          );
      torrentFile('Game.chd', 1000);
      final task = _task('t1', _torrentLink('Game.chd', size: 1000, fileIndex: 1));

      final resultFuture = run(task);
      await waitFor(() => torrents.added.isNotEmpty);
      torrents.progress.add(_tProgress([
        _tFile(0, 'Game.chd', 1000, 1000),
        _tFile(1, 'other.chd', 20, 0),
      ]));
      final result = await resultFuture;

      expect(torrents.added.single.fileIndices, [0]);
      expect(result.status, DownloadStatus.completed);
    });

    test('file missing from the fetched torrent fails without downloading',
        () async {
      http.routes['*'] = (_) => ResponseBody.fromString(
            _multiFileTorrent([('other.chd', 20)]),
            200,
          );
      final task = _task('t1', _torrentLink('Game.chd', size: 1000));

      final result = await run(task);

      expect(result.status, DownloadStatus.failed);
      expect(result.error, contains('not found in torrent'));
      expect(torrents.added, isEmpty);
    });

    test('matching stored index is used as-is', () async {
      http.routes['*'] = (_) => ResponseBody.fromString(
            _multiFileTorrent([('Game.chd', 1000), ('other.chd', 20)]),
            200,
          );
      torrentFile('Game.chd', 1000);
      final task = _task('t1', _torrentLink('Game.chd', size: 1000));

      final resultFuture = run(task);
      await waitFor(() => torrents.added.isNotEmpty);
      torrents.progress.add(_tProgress([_tFile(0, 'Game.chd', 1000, 1000)]));
      final result = await resultFuture;

      expect(torrents.added.single.fileIndices, [0]);
      expect(result.status, DownloadStatus.completed);
    });
  });

  group('torrentFilePaths', () {
    test('parses a multi-file torrent in order', () {
      final bytes =
          _multiFileTorrent([('dir/Game.chd', 10), ('b.chd', 20)]).codeUnits;
      expect(torrentFilePaths(bytes), ['dir/Game.chd', 'b.chd']);
    });

    test('parses a single-file torrent', () {
      const single = 'd4:infod6:lengthi100e4:name8:Game.chdee';
      expect(torrentFilePaths(single.codeUnits), ['Game.chd']);
    });

    test('throws on garbage', () {
      expect(() => torrentFilePaths('not a torrent'.codeUnits),
          throwsA(anything));
    });
  });
}

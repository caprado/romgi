import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/models/models.dart';
import 'package:romgi/services/debrid/debrid_provider.dart';
import 'package:romgi/services/debrid/debrid_registry.dart';
import 'package:romgi/services/debrid_service.dart';
import 'package:romgi/services/download_service.dart';
import 'package:romgi/services/host_adapter.dart';
import 'package:romgi/services/link_resolver.dart';
import 'package:romgi/services/rom_database_service.dart';
import 'package:romgi/services/torrent_service.dart';

import 'debrid/debrid_test_utils.dart';
import 'download_test_utils.dart';

class _Provider implements DebridProvider {
  _Provider(this.result);

  final DebridResult result;

  @override
  DebridProviderInfo get info =>
      const DebridProviderInfo(id: 'torbox', name: 'TorBox');

  @override
  bool isConfigured(String? apiKey) => apiKey != null && apiKey.isNotEmpty;

  @override
  Future<String?> validateKey(String apiKey) async => null;

  @override
  Future<DebridResult> resolveFile(DebridFileRequest req,
          {required String apiKey}) async =>
      result;
}

class _RomDb extends Fake implements RomDatabaseService {
  @override
  Future<TorrentMetadata?> getTorrentMetadata(String infohash) async => null;
}

class _Torrents extends Fake implements TorrentService {
  int starts = 0;

  @override
  Future<void> start({required bool seedingEnabled}) {
    starts++;
    return Completer<void>().future;
  }
}

const _torrentLink = DownloadLink(
  name: 'rom',
  type: 'Game',
  format: 'chd',
  url: '',
  filename: 'Game.chd',
  host: 'MiNERVA Archive',
  size: 1000,
  sizeStr: '1K',
  sourceUrl: '',
  sourceId: 'minerva',
  torrentInfohash: 'aabbccddeeff00112233445566778899aabbccdd',
  torrentFileIndex: 0,
  torrentFilePath: 'Game.chd',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late FakeDatabaseService db;
  late _Torrents torrents;

  // The queue keeps settling after each test's assertion, so the mock stays
  // registered for the whole file.
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_foreground_task/methods'),
      (call) async => call.method == 'isIgnoringBatteryOptimizations',
    );
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('romgi_debrid_routing');
    db = FakeDatabaseService()..servePendingQueue = true;
    torrents = _Torrents();
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  Future<DownloadService> service({
    required DebridResult result,
    String? apiKey = 'key',
    bool torrentsDisabled = false,
  }) async {
    final debrid = DebridService(
      romDb: _RomDb(),
      registry: DebridProviderRegistry(providers: [_Provider(result)]),
      storage: InMemorySecureStorage({}),
    );
    if (apiKey != null) {
      await debrid.setCredentials(providerId: 'torbox', apiKey: apiKey);
    }
    return DownloadService(
      db: db,
      romDb: FakeRomDatabaseService(),
      storage: FakeStorageService(tempDir),
      notifications: FakeNotificationService(),
      adapters: HostAdapterRegistry(),
      torrents: torrents,
      sevenZip: FakeSevenZipService(),
      debrid: debrid,
      dio: Dio(),
    )..getLinkResolverPrefs = () => LinkResolverPrefs(
          debridEnabled: true,
          torrentsDisabled: torrentsDisabled,
        );
  }

  void queue({bool p2pApproved = false}) {
    db.rows['t'] = DownloadTask(
      id: 't',
      slug: 'game',
      title: 'Game',
      platform: 'psx',
      link: _torrentLink,
      createdAt: DateTime(2026),
      p2pApproved: p2pApproved,
    );
  }

  Future<DownloadTask> run(DownloadService s, DownloadStatus status) {
    final done = s.downloadStream
        .firstWhere((t) => t.id == 't' && t.status == status);
    s.setMaxConcurrentDownloads(1);
    return done.timeout(const Duration(seconds: 5));
  }

  test('debrid miss fails and asks instead of starting P2P', () async {
    final s = await service(result: const DebridNotCached());
    queue();

    final failed = await run(s, DownloadStatus.failed);
    expect(failed.needsP2pApproval, isTrue);
    expect(failed.error, contains('TorBox'));
    expect(torrents.starts, 0);
  });

  test('debrid miss with torrents disabled does not offer P2P', () async {
    final s = await service(
      result: const DebridNotCached(),
      torrentsDisabled: true,
    );
    queue();

    final failed = await run(s, DownloadStatus.failed);
    expect(failed.needsP2pApproval, isFalse);
    expect(torrents.starts, 0);
  });

  test('missing API key fails instead of starting P2P', () async {
    final s = await service(
      result: const DebridReady('https://cdn/x'),
      apiKey: null,
    );
    queue();

    final failed = await run(s, DownloadStatus.failed);
    expect(failed.error, 'No TorBox API key saved');
    expect(failed.needsP2pApproval, isTrue);
    expect(torrents.starts, 0);
  });

  test('approving P2P skips debrid and starts the torrent', () async {
    final s = await service(result: const DebridNotCached());
    queue();
    await run(s, DownloadStatus.failed);

    final started = s.downloadStream.firstWhere(
        (t) => t.id == 't' && t.status == DownloadStatus.downloading);
    await s.downloadViaTorrent('t');
    s.setMaxConcurrentDownloads(1);
    final task = await started.timeout(const Duration(seconds: 5));

    for (var i = 0; i < 100 && torrents.starts == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(task.p2pApproved, isTrue);
    expect(task.needsP2pApproval, isFalse);
    expect(torrents.starts, 1);
  });

  test('retry clears approval so debrid is tried again', () async {
    final s = await service(result: const DebridNotCached());
    queue(p2pApproved: true);
    db.rows['t'] = db.rows['t']!.copyWith(
      status: DownloadStatus.failed,
      needsP2pApproval: true,
    );

    final failed = s.downloadStream.firstWhere(
        (t) => t.id == 't' && t.status == DownloadStatus.failed);
    await s.retryDownload('t');
    s.setMaxConcurrentDownloads(1);
    final task = await failed.timeout(const Duration(seconds: 5));

    expect(task.needsP2pApproval, isTrue);
    expect(torrents.starts, 0);
  });

  test('approval flags survive a toMap/fromMap round-trip', () {
    final task = DownloadTask(
      id: 'id',
      slug: 'slug',
      title: 'title',
      platform: 'psx',
      link: _torrentLink,
      createdAt: DateTime(2026),
      p2pApproved: true,
      needsP2pApproval: true,
    );
    final back = DownloadTask.fromMap(task.toMap());
    expect(back.p2pApproved, isTrue);
    expect(back.needsP2pApproval, isTrue);
  });
}

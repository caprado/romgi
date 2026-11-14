import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/models/models.dart';
import 'package:romgi/services/download_service.dart';
import 'package:romgi/services/host_adapter.dart';
import 'package:romgi/services/torrent_service.dart';
import 'package:romgi/services/vpn_service.dart';

import 'download_test_utils.dart';

class _Vpn implements VpnService {
  bool active = false;
  final _changes = StreamController<bool>.broadcast();

  void set(bool value) {
    active = value;
    _changes.add(value);
  }

  @override
  Future<bool> isActive() async => active;

  @override
  Stream<bool> get changes => _changes.stream;
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
  late _Vpn vpn;
  late DownloadService service;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_foreground_task/methods'),
      (call) async => call.method == 'isIgnoringBatteryOptimizations',
    );
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('romgi_vpn');
    db = FakeDatabaseService()..servePendingQueue = true;
    torrents = _Torrents();
    vpn = _Vpn();
    service = DownloadService(
      db: db,
      romDb: FakeRomDatabaseService(),
      storage: FakeStorageService(tempDir),
      notifications: FakeNotificationService(),
      adapters: HostAdapterRegistry(),
      torrents: torrents,
      sevenZip: FakeSevenZipService(),
      vpn: vpn,
      dio: Dio(),
    )..requireVpnForTorrents = () => true;
    db.rows['t'] = DownloadTask(
      id: 't',
      slug: 'game',
      title: 'Game',
      platform: 'psx',
      link: _torrentLink,
      createdAt: DateTime(2026),
    );
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  Future<DownloadTask> next(DownloadStatus status) => service.downloadStream
      .firstWhere((t) => t.id == 't' && t.status == status)
      .timeout(const Duration(seconds: 5));

  test('refuses to start a torrent without a VPN', () async {
    final failed = next(DownloadStatus.failed);
    service.setMaxConcurrentDownloads(1);

    expect((await failed).error, 'Connect to a VPN to download torrents');
    expect(torrents.starts, 0);
  });

  test('starts the torrent when a VPN is up', () async {
    vpn.active = true;
    final started = next(DownloadStatus.downloading);
    service.setMaxConcurrentDownloads(1);

    await started;
    for (var i = 0; i < 100 && torrents.starts == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(torrents.starts, 1);
  });

  test('pauses on VPN drop and resumes when it reconnects', () async {
    vpn.active = true;
    final started = next(DownloadStatus.downloading);
    service.setMaxConcurrentDownloads(1);
    await started;

    final paused = next(DownloadStatus.paused);
    vpn.set(false);
    await paused;

    final resumed = next(DownloadStatus.downloading);
    vpn.set(true);
    await resumed;
  });

  test('VPN changes are ignored when the setting is off', () async {
    service.requireVpnForTorrents = () => false;
    final started = next(DownloadStatus.downloading);
    service.setMaxConcurrentDownloads(1);
    await started;

    var paused = false;
    final sub = service.downloadStream
        .where((t) => t.status == DownloadStatus.paused)
        .listen((_) => paused = true);
    vpn.set(false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(paused, isFalse);
  });
}

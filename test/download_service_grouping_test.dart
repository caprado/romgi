import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:romgi/models/models.dart';
import 'package:romgi/services/database_service.dart';
import 'package:romgi/services/download_service.dart';
import 'package:romgi/services/host_adapter.dart';
import 'package:romgi/services/link_resolver.dart';
import 'package:romgi/services/notification_service.dart';
import 'package:romgi/services/playlist_writer.dart';
import 'package:romgi/services/rom_database_service.dart';
import 'package:romgi/services/seven_zip_service.dart';
import 'package:romgi/services/storage_service.dart';
import 'package:romgi/services/torrent_service.dart';

class FakeDatabaseService extends Fake implements DatabaseService {
  final Map<String, DownloadTask> rows = {};

  // When false the pending queue reports empty, so freshly queued tasks
  // never start real downloads.
  bool servePendingQueue = false;

  DownloadTask bySlug(String slug) =>
      rows.values.firstWhere((t) => t.slug == slug);

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
  Future<DownloadTask?> findExistingDownload(String slug) async {
    for (final task in rows.values) {
      if (task.slug == slug && task.status != DownloadStatus.failed) {
        return task;
      }
    }
    return null;
  }

  @override
  Future<List<DownloadTask>> getDownloadsByGroup(String groupId) async {
    return rows.values.where((t) => t.groupId == groupId).toList()
      ..sort((a, b) => (a.groupIndex ?? 0).compareTo(b.groupIndex ?? 0));
  }

  @override
  Future<List<DownloadTask>> getDownloadsByStatus(DownloadStatus status) async {
    if (!servePendingQueue && status == DownloadStatus.pending) return [];
    return rows.values.where((t) => t.status == status).toList();
  }

  @override
  Future<void> updateDownloadGroup(
    String id, {
    required String groupId,
    int? groupIndex,
    String? groupTitle,
    int? groupTotal,
  }) async {
    final task = rows[id];
    if (task == null) return;
    rows[id] = task.copyWith(
      error: task.error,
      groupId: groupId,
      groupIndex: groupIndex,
      groupTitle: groupTitle,
      groupTotal: groupTotal,
    );
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
  final Map<String, RomEntry> entries = {};

  @override
  Future<RomEntry?> getEntry(String slug) async => entries[slug];
}

class FakeTorrentService extends Fake implements TorrentService {}

class FakeSevenZipService extends Fake implements SevenZipService {}

DownloadLink _httpLink(String filename) => DownloadLink(
      name: 'rom',
      type: 'Game',
      format: 'chd',
      url: 'https://host/$filename',
      filename: filename,
      host: 'host',
      size: 1000,
      sizeStr: '1K',
      sourceUrl: 'https://host/',
      sourceId: 'host',
    );

DownloadLink _torrentLink(String filename, {required int size}) => DownloadLink(
      name: 'rom',
      type: 'Game',
      format: 'chd',
      url: 'https://host/$filename',
      filename: filename,
      host: 'MiNERVA Archive',
      size: size,
      sizeStr: '$size B',
      sourceUrl: 'https://host/',
      sourceId: 'minerva',
      torrentInfohash: 'aabbccddeeff00112233445566778899aabbccdd',
      torrentFileIndex: 0,
      torrentFilePath: filename,
    );

RomEntry _entry(String slug, String title) => RomEntry(
      slug: slug,
      title: title,
      platform: 'psx',
      regions: const ['us'],
      links: [_httpLink('$title.chd')],
    );

EntryGroup _group() => const EntryGroup(
      id: 'disc:psx:game',
      kind: 'disc',
      title: 'Game',
      platform: 'psx',
      members: [
        EntryGroupMember(
          slug: 'game-disc-1',
          title: 'Game (Disc 1)',
          index: 1,
          label: 'Disc 1',
        ),
        EntryGroupMember(
          slug: 'game-disc-2',
          title: 'Game (Disc 2)',
          index: 2,
          label: 'Disc 2',
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late FakeDatabaseService db;
  late FakeRomDatabaseService romDb;
  late DownloadService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('romgi_grouping_test');
    db = FakeDatabaseService();
    romDb = FakeRomDatabaseService();
    service = DownloadService(
      db: db,
      romDb: romDb,
      storage: FakeStorageService(tempDir),
      notifications: FakeNotificationService(),
      adapters: HostAdapterRegistry(),
      torrents: FakeTorrentService(),
      sevenZip: FakeSevenZipService(),
      dio: Dio(),
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
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_foreground_task/methods'),
      null,
    );
    tempDir.deleteSync(recursive: true);
  });

  String discFile(String name) {
    final path = p.join(tempDir.path, name);
    File(path).writeAsStringSync('data');
    return path;
  }

  DownloadTask completedStandalone(String slug, String title) => DownloadTask(
        id: slug,
        slug: slug,
        title: title,
        platform: 'psx',
        link: _httpLink('$title.chd'),
        status: DownloadStatus.completed,
        progress: 1.0,
        filePath: discFile('$title.chd'),
        createdAt: DateTime(2026),
        completedAt: DateTime(2026),
      );

  File playlistFile() => File(p.join(tempDir.path, 'Game.m3u'));

  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 250 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  group('addDiscGroup backfill', () {
    test(
        'backfills group metadata onto standalone rows and writes the '
        'playlist when the whole set is already complete', () async {
      final disc1 = completedStandalone('game-disc-1', 'Game (Disc 1)');
      final disc2 = completedStandalone('game-disc-2', 'Game (Disc 2)');
      db.rows[disc1.id] = disc1;
      db.rows[disc2.id] = disc2;
      romDb.entries['game-disc-1'] = _entry('game-disc-1', 'Game (Disc 1)');
      romDb.entries['game-disc-2'] = _entry('game-disc-2', 'Game (Disc 2)');

      final result = await service.addDiscGroup(
        _group(),
        prefs: const LinkResolverPrefs(),
      );

      expect(result.added, 0);
      expect(result.duplicates, 2);

      final row1 = db.bySlug('game-disc-1');
      expect(row1.groupId, 'disc:psx:game');
      expect(row1.groupIndex, 1);
      expect(row1.groupTitle, 'Game');
      expect(row1.groupTotal, 2);
      expect(db.bySlug('game-disc-2').groupId, 'disc:psx:game');

      expect(playlistFile().existsSync(), isTrue);
      expect(
        playlistFile().readAsStringSync(),
        'Game (Disc 1).chd\nGame (Disc 2).chd\n',
      );
    });

    test(
        'backfilled disc no longer blocks the playlist once the remaining '
        'disc completes', () async {
      final disc1 = completedStandalone('game-disc-1', 'Game (Disc 1)');
      db.rows[disc1.id] = disc1;
      romDb.entries['game-disc-1'] = _entry('game-disc-1', 'Game (Disc 1)');
      romDb.entries['game-disc-2'] = _entry('game-disc-2', 'Game (Disc 2)');

      final result = await service.addDiscGroup(
        _group(),
        prefs: const LinkResolverPrefs(),
      );

      expect(result.added, 1);
      expect(result.duplicates, 1);
      expect(db.bySlug('game-disc-1').groupId, 'disc:psx:game');
      expect(db.bySlug('game-disc-2').status, DownloadStatus.pending);
      expect(playlistFile().existsSync(), isFalse);

      final pending = db.bySlug('game-disc-2');
      final completed = pending.copyWith(
        status: DownloadStatus.completed,
        progress: 1.0,
        filePath: discFile('Game (Disc 2).chd'),
        completedAt: DateTime(2026),
      );
      db.rows[completed.id] = completed;
      final writer = PlaylistWriter(
        getGroupMembers: db.getDownloadsByGroup,
        getPlatformDirectory: (_) async => tempDir,
      );
      await writer.maybeWritePlaylist(completed);

      expect(playlistFile().existsSync(), isTrue);
      expect(
        playlistFile().readAsStringSync(),
        'Game (Disc 1).chd\nGame (Disc 2).chd\n',
      );
    });
  });

  group('torrent alreadyComplete shortcut', () {
    test('writes the playlist when the last disc short-circuits to completed',
        () async {
      final disc1File = discFile('Game (Disc 1).chd');
      db.rows['d1'] = DownloadTask(
        id: 'd1',
        slug: 'game-disc-1',
        title: 'Game (Disc 1)',
        platform: 'psx',
        link: _httpLink('Game (Disc 1).chd'),
        status: DownloadStatus.completed,
        progress: 1.0,
        filePath: disc1File,
        createdAt: DateTime(2026),
        completedAt: DateTime(2026),
        groupId: 'disc:psx:game',
        groupIndex: 1,
        groupTitle: 'Game',
        groupTotal: 2,
      );

      final disc2File = discFile('Game (Disc 2).chd');
      db.rows['d2'] = DownloadTask(
        id: 'd2',
        slug: 'game-disc-2',
        title: 'Game (Disc 2)',
        platform: 'psx',
        link: _torrentLink(
          'Game (Disc 2).chd',
          size: File(disc2File).lengthSync(),
        ),
        status: DownloadStatus.pending,
        createdAt: DateTime(2026),
        groupId: 'disc:psx:game',
        groupIndex: 2,
        groupTitle: 'Game',
        groupTotal: 2,
      );
      db.servePendingQueue = true;

      final completedFuture = service.downloadStream.firstWhere(
        (t) => t.id == 'd2' && t.status == DownloadStatus.completed,
      );

      service.setMaxConcurrentDownloads(1);
      await completedFuture.timeout(const Duration(seconds: 5));

      await waitFor(() => playlistFile().existsSync());
      expect(playlistFile().existsSync(), isTrue);
      expect(
        playlistFile().readAsStringSync(),
        'Game (Disc 1).chd\nGame (Disc 2).chd\n',
      );
      expect(db.rows['d2']!.status, DownloadStatus.completed);
    });
  });

  group('DownloadTask group fields', () {
    test('survive a toMap/fromMap round-trip', () {
      final task = DownloadTask(
        id: 'id',
        slug: 'slug',
        title: 'Game (Disc 1)',
        platform: 'psx',
        link: _httpLink('Game (Disc 1).chd'),
        createdAt: DateTime(2026),
        groupId: 'disc:psx:game',
        groupIndex: 1,
        groupTitle: 'Game',
        groupTotal: 2,
      );

      final restored = DownloadTask.fromMap(task.toMap());

      expect(restored.groupId, 'disc:psx:game');
      expect(restored.groupIndex, 1);
      expect(restored.groupTitle, 'Game');
      expect(restored.groupTotal, 2);
    });

    test('survive copyWith and can be set via copyWith', () {
      final task = DownloadTask(
        id: 'id',
        slug: 'slug',
        title: 'Game (Disc 1)',
        platform: 'psx',
        link: _httpLink('Game (Disc 1).chd'),
        createdAt: DateTime(2026),
        groupId: 'disc:psx:game',
        groupIndex: 1,
        groupTitle: 'Game',
        groupTotal: 2,
      );

      final updated = task.copyWith(status: DownloadStatus.completed);
      expect(updated.groupId, 'disc:psx:game');
      expect(updated.groupIndex, 1);
      expect(updated.groupTitle, 'Game');
      expect(updated.groupTotal, 2);

      final standalone = DownloadTask(
        id: 'solo',
        slug: 'solo',
        title: 'Solo',
        platform: 'psx',
        link: _httpLink('Solo.chd'),
        createdAt: DateTime(2026),
      );
      final backfilled = standalone.copyWith(
        groupId: 'disc:psx:game',
        groupIndex: 2,
        groupTitle: 'Game',
        groupTotal: 2,
      );
      expect(backfilled.groupId, 'disc:psx:game');
      expect(backfilled.groupIndex, 2);
      expect(backfilled.groupTitle, 'Game');
      expect(backfilled.groupTotal, 2);
    });
  });
}

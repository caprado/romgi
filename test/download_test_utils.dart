import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:romgi/models/models.dart';
import 'package:romgi/services/database_service.dart';
import 'package:romgi/services/notification_service.dart';
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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/models/models.dart';
import 'package:romgi/providers/download_provider.dart';
import 'package:romgi/providers/library_provider.dart';
import 'package:romgi/screens/library_screen.dart';
import 'package:romgi/services/database_service.dart';
import 'package:romgi/services/storage_service.dart';

class LibraryDatabase extends Fake implements DatabaseService {
  final List<DownloadTask> rows = [];

  @override
  Future<List<DownloadTask>> getCompletedDownloads() async => [...rows];

  @override
  Future<void> deleteDownload(String id) async {
    rows.removeWhere((row) => row.id == id);
  }

  @override
  Future<List<Favorite>> getFavorites() async => [];
}

DownloadTask task(String id, String? path) => DownloadTask(
  id: id,
  slug: id,
  title: id,
  platform: 'ps1',
  filePath: path,
  status: DownloadStatus.completed,
  createdAt: DateTime(2026),
  link: const DownloadLink(
    name: 'Game',
    type: 'rom',
    format: 'zip',
    url: '',
    filename: 'game.zip',
    host: '',
    size: 0,
    sizeStr: '0 B',
    sourceUrl: '',
  ),
);

void main() {
  late Directory root;
  late StorageService storage;
  late LibraryDatabase db;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('romgi-library-');
    storage = StorageService();
    db = LibraryDatabase();
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'refresh and verification accept files and extraction directories',
    () async {
      final file = await File('${root.path}/single.chd').create();
      final folder = await Directory('${root.path}/Castlevania').create();
      await File('${folder.path}/game.cue').create();
      await File('${folder.path}/game.bin').create();
      final nested = await Directory(
        '${root.path}/nested/disc',
      ).create(recursive: true);
      await File('${nested.path}/game.bin').create();
      final deleted = await File('${root.path}/deleted.chd').create();
      await deleted.delete();
      db.rows.addAll([
        task('single', file.path),
        task('multi', folder.path),
        task('nested', nested.parent.path),
        task('deleted', deleted.path),
        task('null', null),
      ]);
      final notifier = LibraryNotifier(db, storage);
      addTearDown(notifier.dispose);
      await notifier.refresh();
      final expected = {file.path, folder.path, nested.parent.path};
      expect(notifier.state.verifiedFiles, expected);
      expect(notifier.state.fileExists(null), isFalse);
      await notifier.verifyFiles();
      expect(notifier.state.verifiedFiles, expected);
      await folder.delete(recursive: true);
      await notifier.verifyFiles();
      expect(notifier.state.fileExists(folder.path), isFalse);
    },
  );

  test('cleanup rechecks stale results before deleting records', () async {
    final restored = Directory('${root.path}/restored');
    final removed = await File('${root.path}/removed.chd').create();
    db.rows.addAll([
      task('restored', restored.path),
      task('removed', removed.path),
      task('null', null),
    ]);
    final notifier = LibraryNotifier(db, storage);
    addTearDown(notifier.dispose);
    await notifier.refresh();
    expect(notifier.state.fileExists(restored.path), isFalse);
    await restored.create();
    await removed.delete();
    await notifier.cleanupMissingFiles();
    expect(db.rows.map((row) => row.id), ['restored', 'null']);
    expect(notifier.state.fileExists(restored.path), isTrue);
  });

  for (final directory in [true, false]) {
    testWidgets('file info for ${directory ? "folder" : "file"} downloads', (
      tester,
    ) async {
      final path = '${root.path}/game';
      await tester.runAsync(() async {
        if (directory) {
          await Directory(path).create();
          await File('$path/game.cue').create();
          await File('$path/game.bin').create();
        } else {
          await File(path).create();
        }
      });
      db.rows.add(task('Castlevania', path));
      final container = ProviderContainer(
        overrides: [
          databaseServiceProvider.overrideWithValue(db),
          storageServiceProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);
      await tester.runAsync(
        () => container.read(libraryProvider.notifier).refresh(),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Castlevania'));
      });
      // File-system futures run outside the widget test's fake clock.
      for (
        var attempt = 0;
        attempt < 100 && find.byType(AlertDialog).evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(path), findsOneWidget);
      expect(find.text('File no longer exists'), findsNothing);
      expect(
        find.text('Open with...'),
        directory ? findsNothing : findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }
}

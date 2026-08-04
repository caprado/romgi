import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:romgi/models/download_link.dart';
import 'package:romgi/models/download_task.dart';
import 'package:romgi/services/playlist_writer.dart';

DownloadLink _link(String filename) => DownloadLink(
      name: 'rom',
      type: 'Game',
      format: 'chd',
      url: 'https://host/$filename',
      filename: filename,
      host: 'host',
      size: 1000,
      sizeStr: '1K',
      sourceUrl: 'https://host/',
    );

DownloadTask _disc({
  required String id,
  required String title,
  DownloadStatus status = DownloadStatus.completed,
  String? filePath,
  String? groupId = 'disc:game',
  int? groupIndex,
  String? groupTitle = 'Game',
  int? groupTotal,
}) =>
    DownloadTask(
      id: id,
      slug: id,
      title: title,
      platform: 'psx',
      link: _link('$title.chd'),
      status: status,
      filePath: filePath,
      createdAt: DateTime(2026),
      groupId: groupId,
      groupIndex: groupIndex,
      groupTitle: groupTitle,
      groupTotal: groupTotal,
    );

void main() {
  late Directory tempDir;
  late List<DownloadTask> members;
  late PlaylistWriter writer;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('romgi_playlist_test');
    members = [];
    writer = PlaylistWriter(
      getGroupMembers: (groupId) async =>
          members.where((m) => m.groupId == groupId).toList(),
      getPlatformDirectory: (_) async => tempDir,
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  File playlistFile() => File(p.join(tempDir.path, 'Game.m3u'));

  String discFile(String name) {
    final path = p.join(tempDir.path, name);
    File(path).writeAsStringSync('data');
    return path;
  }

  group('maybeWritePlaylist', () {
    test('writes basenames when all discs complete as single files', () async {
      members = [
        _disc(
          id: 'd1',
          title: 'Game (Disc 1)',
          filePath: discFile('Game (Disc 1).chd'),
          groupIndex: 1,
          groupTotal: 2,
        ),
        _disc(
          id: 'd2',
          title: 'Game (Disc 2)',
          filePath: discFile('Game (Disc 2).chd'),
          groupIndex: 2,
          groupTotal: 2,
        ),
      ];

      await writer.maybeWritePlaylist(members.last);

      expect(playlistFile().existsSync(), isTrue);
      expect(
        playlistFile().readAsStringSync(),
        'Game (Disc 1).chd\nGame (Disc 2).chd\n',
      );
    });

    test('orders entries by disc index regardless of member order', () async {
      members = [
        _disc(
          id: 'd2',
          title: 'Game (Disc 2)',
          filePath: discFile('Game (Disc 2).chd'),
          groupIndex: 2,
          groupTotal: 2,
        ),
        _disc(
          id: 'd1',
          title: 'Game (Disc 1)',
          filePath: discFile('Game (Disc 1).chd'),
          groupIndex: 1,
          groupTotal: 2,
        ),
      ];

      await writer.maybeWritePlaylist(members.first);

      expect(
        playlistFile().readAsStringSync(),
        'Game (Disc 1).chd\nGame (Disc 2).chd\n',
      );
    });

    test('references the .cue inside an extraction directory', () async {
      final discDir = Directory(p.join(tempDir.path, 'Game (Disc 1)'))
        ..createSync();
      File(p.join(discDir.path, 'Game (Disc 1).bin')).writeAsStringSync('bin');
      File(p.join(discDir.path, 'Game (Disc 1).cue')).writeAsStringSync('cue');

      members = [
        _disc(
          id: 'd1',
          title: 'Game (Disc 1)',
          filePath: discDir.path,
          groupIndex: 1,
          groupTotal: 2,
        ),
        _disc(
          id: 'd2',
          title: 'Game (Disc 2)',
          filePath: discFile('Game (Disc 2).chd'),
          groupIndex: 2,
          groupTotal: 2,
        ),
      ];

      await writer.maybeWritePlaylist(members.first);

      expect(
        playlistFile().readAsStringSync(),
        'Game (Disc 1)/Game (Disc 1).cue\nGame (Disc 2).chd\n',
      );
    });

    test('prefers disc images over raw .bin when no cue exists', () async {
      final discDir = Directory(p.join(tempDir.path, 'Game (Disc 1)'))
        ..createSync();
      File(p.join(discDir.path, 'Game (Disc 1).bin')).writeAsStringSync('bin');
      File(p.join(discDir.path, 'Game (Disc 1).chd')).writeAsStringSync('chd');

      members = [
        _disc(
          id: 'd1',
          title: 'Game (Disc 1)',
          filePath: discDir.path,
          groupIndex: 1,
          groupTotal: 2,
        ),
        _disc(
          id: 'd2',
          title: 'Game (Disc 2)',
          filePath: discFile('Game (Disc 2).chd'),
          groupIndex: 2,
          groupTotal: 2,
        ),
      ];

      await writer.maybeWritePlaylist(members.first);

      expect(
        playlistFile().readAsStringSync(),
        'Game (Disc 1)/Game (Disc 1).chd\nGame (Disc 2).chd\n',
      );
    });

    test('skips playlist when a member directory has no playable file',
        () async {
      final discDir = Directory(p.join(tempDir.path, 'Game (Disc 1)'))
        ..createSync();
      File(p.join(discDir.path, 'readme.txt')).writeAsStringSync('nope');

      members = [
        _disc(
          id: 'd1',
          title: 'Game (Disc 1)',
          filePath: discDir.path,
          groupIndex: 1,
          groupTotal: 2,
        ),
        _disc(
          id: 'd2',
          title: 'Game (Disc 2)',
          filePath: discFile('Game (Disc 2).chd'),
          groupIndex: 2,
          groupTotal: 2,
        ),
      ];

      await writer.maybeWritePlaylist(members.first);

      expect(playlistFile().existsSync(), isFalse);
    });

    test('does not write when a group row was hard-deleted', () async {
      members = [
        _disc(
          id: 'd1',
          title: 'Game (Disc 1)',
          filePath: discFile('Game (Disc 1).chd'),
          groupIndex: 1,
          groupTotal: 3,
        ),
        _disc(
          id: 'd3',
          title: 'Game (Disc 3)',
          filePath: discFile('Game (Disc 3).chd'),
          groupIndex: 3,
          groupTotal: 3,
        ),
      ];

      await writer.maybeWritePlaylist(members.first);

      expect(playlistFile().existsSync(), isFalse);
    });

    test('does not write while any member is still incomplete', () async {
      members = [
        _disc(
          id: 'd1',
          title: 'Game (Disc 1)',
          filePath: discFile('Game (Disc 1).chd'),
          groupIndex: 1,
          groupTotal: 2,
        ),
        _disc(
          id: 'd2',
          title: 'Game (Disc 2)',
          status: DownloadStatus.downloading,
          groupIndex: 2,
          groupTotal: 2,
        ),
      ];

      await writer.maybeWritePlaylist(members.first);

      expect(playlistFile().existsSync(), isFalse);
    });

    test('is a no-op for non-grouped tasks', () async {
      final task = _disc(
        id: 'solo',
        title: 'Game',
        filePath: discFile('Game.chd'),
        groupId: null,
        groupTitle: null,
      );

      await writer.maybeWritePlaylist(task);

      expect(tempDir.listSync().whereType<File>().map((f) => f.path),
          isNot(contains(endsWith('.m3u'))));
    });

    test('legacy rows without groupTotal still write when all complete',
        () async {
      members = [
        _disc(
          id: 'd1',
          title: 'Game (Disc 1)',
          filePath: discFile('Game (Disc 1).chd'),
          groupIndex: 1,
        ),
        _disc(
          id: 'd2',
          title: 'Game (Disc 2)',
          filePath: discFile('Game (Disc 2).chd'),
          groupIndex: 2,
        ),
      ];

      await writer.maybeWritePlaylist(members.first);

      expect(playlistFile().existsSync(), isTrue);
    });
  });

  group('playlistFileName', () {
    test('strips characters that are invalid in filenames', () {
      expect(
        writer.playlistFileName('Game: The "Sequel" <2>?'),
        'Game The Sequel 2.m3u',
      );
    });

    test('falls back to a generic name when nothing survives', () {
      expect(writer.playlistFileName('<>:"?*'), 'playlist.m3u');
    });
  });
}

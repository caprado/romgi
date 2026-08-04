import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/models.dart';

/// Writes the `.m3u` playlist for a multi-disc download group once every
/// member has finished.
class PlaylistWriter {
  PlaylistWriter({
    required this.getGroupMembers,
    required this.getPlatformDirectory,
  });

  final Future<List<DownloadTask>> Function(String groupId) getGroupMembers;
  final Future<Directory> Function(String platform) getPlatformDirectory;

  /// In preference order — `.cue` first since it's the playable entry point
  /// of a bin/cue dump.
  static const List<String> playableExtensions = [
    '.cue',
    '.chd',
    '.iso',
    '.gdi',
    '.cdi',
    '.mds',
    '.pbp',
    '.img',
    '.bin',
  ];

  /// Write the group's `.m3u` once every member has finished. Safe to call
  /// for non-grouped tasks (no-op) and idempotent if two members finish
  /// near-simultaneously.
  Future<void> maybeWritePlaylist(DownloadTask task) async {
    final groupId = task.groupId;
    if (groupId == null) return;

    final members = await getGroupMembers(groupId);
    if (members.length < 2) return;
    if (members.any((m) => m.status != DownloadStatus.completed)) return;

    final expectedTotal = _expectedTotal(task, members);
    if (expectedTotal != null) {
      final indices = members.map((m) => m.groupIndex).whereType<int>().toSet();
      if (members.length < expectedTotal || indices.length < expectedTotal) {
        debugPrint(
          'PlaylistWriter: group $groupId has ${members.length} of '
          '$expectedTotal discs — skipping playlist',
        );
        return;
      }
    }

    try {
      await _writePlaylist(task.platform, task.groupTitle, members);
    } catch (e) {
      // A missing playlist is non-fatal — the discs are already on disk.
      debugPrint('PlaylistWriter: failed to write playlist for $groupId: $e');
    }
  }

  int? _expectedTotal(DownloadTask task, List<DownloadTask> members) {
    int? total = task.groupTotal;
    for (final member in members) {
      final memberTotal = member.groupTotal;
      if (memberTotal != null && (total == null || memberTotal > total)) {
        total = memberTotal;
      }
    }
    return total;
  }

  Future<void> _writePlaylist(
    String platform,
    String? groupTitle,
    List<DownloadTask> members,
  ) async {
    final ordered = [...members]
      ..sort((a, b) => (a.groupIndex ?? 0).compareTo(b.groupIndex ?? 0));

    final dir = await getPlatformDirectory(platform);

    // The .m3u sits in the platform dir beside the discs, so entries are
    // referenced relative to it and the emulator resolves them.
    final lines = <String>[];
    for (final member in ordered) {
      final filePath = member.filePath;
      if (filePath == null) continue;
      final entry = await resolvePlaylistEntry(filePath, dir.path);
      if (entry == null) {
        debugPrint(
          'PlaylistWriter: no playable file for "${member.title}" at '
          '$filePath — skipping playlist',
        );
        return;
      }
      lines.add(entry);
    }
    if (lines.length < 2) return;

    final name = playlistFileName(groupTitle ?? ordered.first.title);
    await File(p.join(dir.path, name)).writeAsString('${lines.join('\n')}\n');
  }

  /// The playlist line for a disc at [filePath], relative to [playlistDir].
  /// An extraction directory resolves to the playable file inside it.
  Future<String?> resolvePlaylistEntry(
    String filePath,
    String playlistDir,
  ) async {
    var target = filePath;
    if (await Directory(filePath).exists()) {
      final playable = await _findPlayableFile(Directory(filePath));
      if (playable == null) return null;
      target = playable;
    }
    return p.relative(target, from: playlistDir).replaceAll('\\', '/');
  }

  Future<String?> _findPlayableFile(Directory dir) async {
    final files = <String>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) files.add(entity.path);
    }
    for (final ext in playableExtensions) {
      final matches = files
          .where((f) => p.extension(f).toLowerCase() == ext)
          .toList()
        ..sort();
      if (matches.isNotEmpty) return matches.first;
    }
    return null;
  }

  String playlistFileName(String title) {
    final safe = title
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return '${safe.isEmpty ? 'playlist' : safe}.m3u';
  }
}

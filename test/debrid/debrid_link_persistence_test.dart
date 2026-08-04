import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/models/models.dart';

const _hash = 'abcdef0123456789abcdef0123456789abcdef01';

const _torrentLink = DownloadLink(
  name: 'Game',
  type: 'Game',
  format: 'iso',
  url: '',
  filename: 'game.iso',
  host: 'MiNERVA',
  size: 100,
  sizeStr: '100',
  sourceUrl: '',
  torrentInfohash: _hash,
  torrentFileIndex: 3,
  torrentFilePath: 'pack/game.iso',
);

void main() {
  test('resolved link is HTTP but keeps torrent metadata for re-resolution',
      () {
    final resolved = _torrentLink.copyWith(
      url: 'https://cdn.debrid/game.iso',
      debridResolved: true,
    );
    expect(resolved.isTorrent, isFalse);
    expect(resolved.torrentInfohash, _hash);
    expect(resolved.torrentFileIndex, 3);
    expect(resolved.torrentFilePath, 'pack/game.iso');

    final reverted = resolved.copyWith(debridResolved: false);
    expect(reverted.isTorrent, isTrue);
    expect(reverted.torrentInfohash, _hash);
    expect(reverted.torrentFileIndex, 3);
  });

  test('debridResolved survives the DB round-trip', () {
    final task = DownloadTask(
      id: 'id',
      slug: 'slug',
      title: 'Game',
      platform: 'psx',
      link: _torrentLink.copyWith(
        url: 'https://cdn.debrid/game.iso',
        debridResolved: true,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

    final restored = DownloadTask.fromMap(task.toMap());
    expect(restored.link.debridResolved, isTrue);
    expect(restored.link.isTorrent, isFalse);
    expect(restored.link.torrentInfohash, _hash);
    expect(restored.link.url, 'https://cdn.debrid/game.iso');
  });

  test('rows from before the migration default to not resolved', () {
    final task = DownloadTask(
      id: 'id',
      slug: 'slug',
      title: 'Game',
      platform: 'psx',
      link: _torrentLink,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
    final map = task.toMap()..remove('link_debrid_resolved');

    final restored = DownloadTask.fromMap(map);
    expect(restored.link.debridResolved, isFalse);
    expect(restored.link.isTorrent, isTrue);
  });

  test('debridResolved survives the JSON round-trip', () {
    final resolved = _torrentLink.copyWith(
      url: 'https://cdn.debrid/game.iso',
      debridResolved: true,
    );
    final restored = DownloadLink.fromJson(resolved.toJson());
    expect(restored.debridResolved, isTrue);
    expect(restored.isTorrent, isFalse);
    expect(restored.torrentInfohash, _hash);
  });
}

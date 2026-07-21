import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/models/download_link.dart';
import 'package:romgi/services/link_resolver.dart';

DownloadLink _http() => const DownloadLink(
      name: 'HTTP',
      type: 'Game',
      format: 'iso',
      url: 'https://mirror/game.iso',
      filename: 'game.iso',
      host: 'Myrient',
      size: 100,
      sizeStr: '100',
      sourceUrl: '',
      sourceId: 'minerva',
    );

DownloadLink _torrent() => const DownloadLink(
      name: 'Torrent',
      type: 'Game',
      format: 'iso',
      url: '',
      filename: 'game.iso',
      host: 'MiNERVA',
      size: 100,
      sizeStr: '100',
      sourceUrl: '',
      sourceId: 'minerva',
      torrentInfohash: 'abc',
    );

void main() {
  const resolver = LinkResolver();

  test('debrid keeps torrent links even when torrents are disabled', () {
    final ranked = resolver.rank(
      [_torrent()],
      const LinkResolverPrefs(torrentsDisabled: true, debridEnabled: true),
    );
    expect(ranked, hasLength(1));
  });

  test('without debrid, disabled torrents are dropped', () {
    final ranked = resolver.rank(
      [_torrent()],
      const LinkResolverPrefs(torrentsDisabled: true),
    );
    expect(ranked, isEmpty);
  });

  test('debrid removes the HTTP-over-torrent ranking penalty', () {
    final withoutDebrid = resolver.rank(
      [_http(), _torrent()],
      const LinkResolverPrefs(),
    );
    // Same source priority; HTTP wins by the +1 tiebreak.
    expect(withoutDebrid.first.link.isTorrent, isFalse);
    final httpScore =
        withoutDebrid.firstWhere((r) => !r.link.isTorrent).score;
    final torrentScore =
        withoutDebrid.firstWhere((r) => r.link.isTorrent).score;
    expect(httpScore, greaterThan(torrentScore));

    final withDebrid = resolver.rank(
      [_http(), _torrent()],
      const LinkResolverPrefs(debridEnabled: true),
    );
    final httpScore2 = withDebrid.firstWhere((r) => !r.link.isTorrent).score;
    final torrentScore2 = withDebrid.firstWhere((r) => r.link.isTorrent).score;
    expect(torrentScore2, equals(httpScore2)); // penalty gone
  });
}

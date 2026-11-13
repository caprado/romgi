import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/models/download_link.dart';
import 'package:romgi/services/link_resolver.dart';

DownloadLink _http({
  required String host,
  required String sourceId,
  bool requiresAuth = false,
}) =>
    DownloadLink(
      name: 'rom',
      type: 'Game',
      format: 'zip',
      url: 'https://$host/file.zip',
      filename: 'file.zip',
      host: host,
      size: 1000,
      sizeStr: '1K',
      sourceUrl: 'https://$host/',
      sourceId: sourceId,
      requiresAuth: requiresAuth,
    );

DownloadLink _torrent({required String sourceId}) => DownloadLink(
      name: 'rom',
      type: 'Game',
      format: 'zip',
      url: 'https://x/file.torrent',
      filename: 'file.zip',
      host: 'MiNERVA Archive',
      size: 1000,
      sizeStr: '1K',
      sourceUrl: 'https://x/',
      sourceId: sourceId,
      torrentInfohash: 'aabbccddeeff00112233445566778899aabbccdd',
      torrentFileIndex: 0,
      torrentFilePath: 'file.zip',
    );

void main() {
  group('LinkResolver.rank', () {
    test('higher manifest priority ranks first', () {
      final resolver = LinkResolver(sourcePriority: const {
        'minerva': 200,
        'internet_archive': 50,
        'mariocube': 70,
      });
      final ranked = resolver.rank(
        [
          _torrent(sourceId: 'minerva'),
          _http(host: 'archive.org', sourceId: 'internet_archive'),
          _http(host: 'mariocube.com', sourceId: 'mariocube'),
        ],
        const LinkResolverPrefs(isIaLoggedIn: true),
      );
      expect(
        ranked.map((r) => r.link.sourceId),
        ['minerva', 'mariocube', 'internet_archive'],
      );
    });

    test('drops links from disabled sources', () {
      final resolver = LinkResolver(sourcePriority: const {'a': 1, 'b': 2});
      final ranked = resolver.rank(
        [
          _http(host: 'x', sourceId: 'a'),
          _http(host: 'y', sourceId: 'b'),
        ],
        const LinkResolverPrefs(disabledSourceIds: {'a'}),
      );
      expect(ranked.map((r) => r.link.sourceId), ['b']);
    });

    test('preferred source gets a large boost', () {
      final resolver = LinkResolver(sourcePriority: const {
        'minerva': 200,
        'internet_archive': 50,
      });
      final ranked = resolver.rank(
        [
          _torrent(sourceId: 'minerva'),
          _http(host: 'archive.org', sourceId: 'internet_archive'),
        ],
        const LinkResolverPrefs(
          preferredSourceIds: {'internet_archive'},
          isIaLoggedIn: true,
        ),
      );
      expect(ranked.first.link.sourceId, 'internet_archive');
    });

    test('auth-required links sink to the bottom when logged out', () {
      final resolver = LinkResolver(sourcePriority: const {
        'internet_archive': 50,
        'mariocube': 70,
      });
      final ranked = resolver.rank(
        [
          _http(
            host: 'archive.org',
            sourceId: 'internet_archive',
            requiresAuth: true,
          ),
          _http(host: 'mariocube.com', sourceId: 'mariocube'),
        ],
        const LinkResolverPrefs(isIaLoggedIn: false),
      );
      expect(ranked.first.link.sourceId, 'mariocube');
      expect(ranked.last.link.sourceId, 'internet_archive');
      expect(ranked.last.notice, contains('login'));
    });

    test('http and torrent break ties in favor of http', () {
      final resolver = LinkResolver(sourcePriority: const {
        'minerva': 100,
        'internet_archive': 100,
      });
      final ranked = resolver.rank(
        [
          _torrent(sourceId: 'minerva'),
          _http(host: 'archive.org', sourceId: 'internet_archive'),
        ],
        const LinkResolverPrefs(isIaLoggedIn: true),
      );
      expect(ranked.first.link.isTorrent, isFalse);
    });

    test('handles missing sourceId without crashing', () {
      final resolver = LinkResolver(sourcePriority: const {'minerva': 100});
      final ranked = resolver.rank(
        [
          DownloadLink(
            name: 'old',
            type: 'Game',
            format: 'zip',
            url: 'https://x/y.zip',
            filename: 'y.zip',
            host: 'X',
            size: 1,
            sizeStr: '1',
            sourceUrl: 'https://x/',
          ),
          _torrent(sourceId: 'minerva'),
        ],
        const LinkResolverPrefs(),
      );
      expect(ranked.map((r) => r.link.sourceId), ['minerva', null]);
    });
  });
}

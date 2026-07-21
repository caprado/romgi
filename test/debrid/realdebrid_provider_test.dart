import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/services/debrid/debrid_provider.dart';
import 'package:romgi/services/debrid/realdebrid_provider.dart';

import 'debrid_test_utils.dart';

const _base = 'https://api.real-debrid.com/rest/1.0';
const _hash = 'abcdef0123456789abcdef0123456789abcdef01';

DebridFileRequest _req({String? filePath}) => DebridFileRequest(
      infohash: _hash,
      magnet: 'magnet:?xt=urn:btih:$_hash',
      fileIndex: 0,
      filePath: filePath,
    );

void main() {
  test('downloaded torrent unrestricts to a ready link', () async {
    final dio = stubbedDio(_base, {
      '/rest/1.0/torrents': (_) => jsonBody('[]'),
      '/rest/1.0/torrents/addMagnet': (_) => jsonBody('{"id":"123"}'),
      '/rest/1.0/torrents/info/123': (_) => jsonBody(
          '{"status":"downloaded","progress":100,'
          '"files":[{"id":1,"path":"/game.iso","bytes":1000,"selected":1}],'
          '"links":["https://real/link1"]}'),
      '/rest/1.0/unrestrict/link': (_) =>
          jsonBody('{"download":"https://cdn.rd/game.iso","filename":"game.iso","filesize":1000}'),
    });

    final result = await RealDebridProvider(dio: dio).resolveFile(_req(), apiKey: 'k');
    expect(result, isA<DebridReady>());
    expect((result as DebridReady).url, 'https://cdn.rd/game.iso');
  });

  test('waiting_files_selection selects the file and reports caching', () async {
    final stub = StubAdapter({
      '/rest/1.0/torrents': (_) => jsonBody('[]'),
      '/rest/1.0/torrents/addMagnet': (_) => jsonBody('{"id":"55"}'),
      '/rest/1.0/torrents/info/55': (_) => jsonBody(
          '{"status":"waiting_files_selection","progress":0,'
          '"files":[{"id":1,"path":"/g.iso","bytes":10,"selected":0}],"links":[]}'),
      '/rest/1.0/torrents/selectFiles/55': (_) => jsonBody('', 204),
    });
    final dio = stubbedDio(_base, stub.routes)..httpClientAdapter = stub;

    final result = await RealDebridProvider(dio: dio).resolveFile(_req(), apiKey: 'k');
    expect(result, isA<DebridCaching>());
    expect(
      stub.calls.any((c) => c.uri.path.endsWith('/selectFiles/55')),
      isTrue,
    );
  });

  test('downloading torrent reports caching with normalized progress', () async {
    final dio = stubbedDio(_base, {
      '/rest/1.0/torrents': (_) => jsonBody('[]'),
      '/rest/1.0/torrents/addMagnet': (_) => jsonBody('{"id":"1"}'),
      '/rest/1.0/torrents/info/1': (_) =>
          jsonBody('{"status":"downloading","progress":42,"files":[],"links":[]}'),
    });
    final result = await RealDebridProvider(dio: dio).resolveFile(_req(), apiKey: 'k');
    expect((result as DebridCaching).progress, closeTo(0.42, 1e-9));
  });

  test('dead torrent is not cached', () async {
    final dio = stubbedDio(_base, {
      '/rest/1.0/torrents': (_) => jsonBody('[]'),
      '/rest/1.0/torrents/addMagnet': (_) => jsonBody('{"id":"1"}'),
      '/rest/1.0/torrents/info/1': (_) =>
          jsonBody('{"status":"dead","files":[],"links":[]}'),
    });
    final result = await RealDebridProvider(dio: dio).resolveFile(_req(), apiKey: 'k');
    expect(result, isA<DebridNotCached>());
  });

  test('401 surfaces an auth error and sends bearer token', () async {
    final stub = StubAdapter({
      '/rest/1.0/torrents': (_) => jsonBody('[]', 401),
    });
    final dio = stubbedDio(_base, stub.routes)..httpClientAdapter = stub;
    final result = await RealDebridProvider(dio: dio).resolveFile(_req(), apiKey: 'tok');
    expect((result as DebridError).authError, isTrue);
    expect(stub.calls.first.headers['Authorization'], 'Bearer tok');
  });
}

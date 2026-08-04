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

  test('pre-existing torrent with a different file selected never returns '
      'the wrong link', () async {
    final stub = StubAdapter({
      '/rest/1.0/torrents': (_) => jsonBody('[{"id":"77","hash":"$_hash"}]'),
      '/rest/1.0/torrents/info/77': (_) => jsonBody(
          '{"status":"downloaded","progress":100,'
          '"files":[{"id":1,"path":"/other.iso","bytes":500,"selected":1},'
          '{"id":2,"path":"/game.iso","bytes":500,"selected":0}],'
          '"links":["https://real/other"]}'),
      '/rest/1.0/torrents/delete/77': (_) => jsonBody('', 204),
    });
    final dio = stubbedDio(_base, stub.routes)..httpClientAdapter = stub;

    final result = await RealDebridProvider(dio: dio)
        .resolveFile(_req(filePath: 'game.iso'), apiKey: 'k');

    expect(result, isNot(isA<DebridReady>()));
    expect(result, isA<DebridCaching>());
    expect(
      stub.calls.any((c) =>
          c.method == 'DELETE' && c.uri.path.endsWith('/torrents/delete/77')),
      isTrue,
    );
    expect(
      stub.calls.any((c) => c.uri.path.endsWith('/unrestrict/link')),
      isFalse,
    );
  });

  test('selectFiles failure surfaces a terminal error, not eternal caching',
      () async {
    final dio = stubbedDio(_base, {
      '/rest/1.0/torrents': (_) => jsonBody('[]'),
      '/rest/1.0/torrents/addMagnet': (_) => jsonBody('{"id":"9"}'),
      '/rest/1.0/torrents/info/9': (_) => jsonBody(
          '{"status":"waiting_files_selection","progress":0,'
          '"files":[{"id":1,"path":"/g.iso","bytes":10,"selected":0}],"links":[]}'),
      '/rest/1.0/torrents/selectFiles/9': (_) =>
          jsonBody('{"error":"bad_request"}', 400),
    });
    final result =
        await RealDebridProvider(dio: dio).resolveFile(_req(), apiKey: 'k');
    expect(result, isA<DebridError>());
    expect((result as DebridError).permanent, isTrue);
  });

  test('torrent deleted server-side (info 404) re-adds instead of looping',
      () async {
    final dio = stubbedDio(_base, {
      '/rest/1.0/torrents': (_) => jsonBody('[{"id":"5","hash":"$_hash"}]'),
      '/rest/1.0/torrents/info/5': (_) =>
          jsonBody('{"error":"unknown_resource","error_code":7}', 404),
    });
    final result =
        await RealDebridProvider(dio: dio).resolveFile(_req(), apiKey: 'k');
    expect(result, isA<DebridCaching>());
  });

  test('find-by-hash scans beyond the first page of torrents', () async {
    final fillerHash = 'f' * 40;
    final page1 = List.generate(
        100, (i) => '{"id":"t$i","hash":"$fillerHash"}').join(',');
    final stub = StubAdapter({
      '/rest/1.0/torrents': (o) => o.uri.queryParameters['page'] == '1'
          ? jsonBody('[$page1]')
          : jsonBody('[{"id":"200","hash":"$_hash"}]'),
      '/rest/1.0/torrents/info/200': (_) => jsonBody(
          '{"status":"downloaded","progress":100,'
          '"files":[{"id":1,"path":"/game.iso","bytes":1000,"selected":1}],'
          '"links":["https://real/link1"]}'),
      '/rest/1.0/unrestrict/link': (_) =>
          jsonBody('{"download":"https://cdn.rd/game.iso"}'),
    });
    final dio = stubbedDio(_base, stub.routes)..httpClientAdapter = stub;

    final result =
        await RealDebridProvider(dio: dio).resolveFile(_req(), apiKey: 'k');
    expect(result, isA<DebridReady>());
    expect(
      stub.calls.any((c) => c.uri.path.endsWith('/addMagnet')),
      isFalse,
    );
  });

  test('validateKey accepts a working token and flags a rejected one',
      () async {
    final ok = stubbedDio(_base, {
      '/rest/1.0/user': (_) => jsonBody('{"id":1,"username":"u"}'),
    });
    expect(await RealDebridProvider(dio: ok).validateKey('k'), isNull);

    final bad = stubbedDio(_base, {
      '/rest/1.0/user': (_) => jsonBody('{"error":"bad_token"}', 401),
    });
    expect(await RealDebridProvider(dio: bad).validateKey('k'),
        'Invalid Real-Debrid token');
  });
}

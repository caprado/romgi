import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/services/debrid/debrid_provider.dart';
import 'package:romgi/services/debrid/torbox_provider.dart';

import 'debrid_test_utils.dart';

const _base = 'https://api.torbox.app/v1/api';
const _hash = 'abcdef0123456789abcdef0123456789abcdef01';

DebridFileRequest _req({int fileIndex = 0, String? filePath, int size = 0}) =>
    DebridFileRequest(
      infohash: _hash,
      magnet: 'magnet:?xt=urn:btih:$_hash',
      fileIndex: fileIndex,
      filePath: filePath,
      expectedSize: size,
    );

void main() {
  test('cached torrent resolves to a ready direct link', () async {
    final dio = stubbedDio(_base, {
      '/v1/api/torrents/createtorrent': (_) =>
          jsonBody('{"success":true,"data":{"torrent_id":42,"hash":"$_hash"}}'),
      '/v1/api/torrents/mylist': (_) => jsonBody(
          '{"success":true,"data":{"id":42,"hash":"$_hash",'
          '"download_present":true,"download_finished":true,"progress":1.0,'
          '"files":[{"id":0,"name":"game.iso","size":1000}]}}'),
      '/v1/api/torrents/requestdl': (_) =>
          jsonBody('{"success":true,"data":"https://cdn.torbox/dl/game.iso"}'),
    });
    final provider = TorboxProvider(dio: dio);

    final result = await provider.resolveFile(_req(), apiKey: 'key');
    expect(result, isA<DebridReady>());
    expect((result as DebridReady).url, 'https://cdn.torbox/dl/game.iso');
  });

  test('still-downloading torrent reports caching with progress', () async {
    final dio = stubbedDio(_base, {
      '/v1/api/torrents/createtorrent': (_) =>
          jsonBody('{"success":true,"data":{"torrent_id":7}}'),
      '/v1/api/torrents/mylist': (_) => jsonBody(
          '{"success":true,"data":{"id":7,"download_present":false,'
          '"download_finished":false,"progress":0.4,"files":[]}}'),
    });
    final provider = TorboxProvider(dio: dio);

    final result = await provider.resolveFile(_req(), apiKey: 'key');
    expect(result, isA<DebridCaching>());
    expect((result as DebridCaching).progress, 0.4);
  });

  test('401 surfaces an auth error', () async {
    final dio = stubbedDio(_base, {
      '/v1/api/torrents/createtorrent': (_) => jsonBody('{"success":false}', 401),
    });
    final result =
        await TorboxProvider(dio: dio).resolveFile(_req(), apiKey: 'bad');
    expect(result, isA<DebridError>());
    expect((result as DebridError).authError, isTrue);
  });

  test('429 surfaces a rate-limit error', () async {
    final dio = stubbedDio(_base, {
      '/v1/api/torrents/createtorrent': (_) => jsonBody('{}', 429),
    });
    final result =
        await TorboxProvider(dio: dio).resolveFile(_req(), apiKey: 'key');
    expect((result as DebridError).rateLimited, isTrue);
  });

  test('multi-file torrent picks the file matching filePath', () async {
    final stub = StubAdapter({
      '/v1/api/torrents/createtorrent': (_) =>
          jsonBody('{"success":true,"data":{"torrent_id":9}}'),
      '/v1/api/torrents/mylist': (_) => jsonBody(
          '{"success":true,"data":{"id":9,"download_present":true,'
          '"download_finished":true,"progress":1.0,"files":['
          '{"id":0,"name":"disc1.iso","size":500},'
          '{"id":1,"name":"disc2.iso","size":500}]}}'),
      '/v1/api/torrents/requestdl': (_) =>
          jsonBody('{"success":true,"data":"https://cdn/disc2"}'),
    });
    final dio = stubbedDio(_base, stub.routes)..httpClientAdapter = stub;

    final result = await TorboxProvider(dio: dio)
        .resolveFile(_req(fileIndex: 0, filePath: 'game/disc2.iso'), apiKey: 'k');

    expect((result as DebridReady).url, 'https://cdn/disc2');
    final requestdl = stub.calls.firstWhere(
      (c) => c.uri.path.endsWith('/requestdl'),
    );
    expect(requestdl.uri.queryParameters['file_id'], '1');
    // And the bearer header was sent.
    expect(requestdl.headers['Authorization'], 'Bearer k');
  });

  test('success:false with ACTIVE_LIMIT is a terminal error, not caching',
      () async {
    final dio = stubbedDio(_base, {
      '/v1/api/torrents/createtorrent': (_) => jsonBody(
          '{"success":false,"error":"ACTIVE_LIMIT",'
          '"detail":"Active torrent limit reached","data":null}'),
    });
    final result =
        await TorboxProvider(dio: dio).resolveFile(_req(), apiKey: 'k');
    expect(result, isA<DebridError>());
    final error = result as DebridError;
    expect(error.permanent, isTrue);
    expect(error.authError, isFalse);
    expect(error.message, contains('Active torrent limit reached'));
  });

  test('success:false with an invalid magnet is a terminal error', () async {
    final dio = stubbedDio(_base, {
      '/v1/api/torrents/createtorrent': (_) =>
          jsonBody('{"success":false,"error":"INVALID_MAGNET","data":null}'),
    });
    final result =
        await TorboxProvider(dio: dio).resolveFile(_req(), apiKey: 'k');
    expect((result as DebridError).permanent, isTrue);
  });

  test('success:false auth code is surfaced as an auth error', () async {
    final dio = stubbedDio(_base, {
      '/v1/api/torrents/createtorrent': (_) => jsonBody(
          '{"success":false,"error":"BAD_TOKEN","detail":"Invalid key",'
          '"data":null}'),
    });
    final result =
        await TorboxProvider(dio: dio).resolveFile(_req(), apiKey: 'k');
    expect((result as DebridError).authError, isTrue);
  });

  test('success:false on requestdl is surfaced instead of a bogus link',
      () async {
    final dio = stubbedDio(_base, {
      '/v1/api/torrents/createtorrent': (_) =>
          jsonBody('{"success":true,"data":{"torrent_id":42}}'),
      '/v1/api/torrents/mylist': (_) => jsonBody(
          '{"success":true,"data":{"id":42,"hash":"$_hash",'
          '"download_present":true,"download_finished":true,"progress":1.0,'
          '"files":[{"id":0,"name":"game.iso","size":1000}]}}'),
      '/v1/api/torrents/requestdl': (_) => jsonBody(
          '{"success":false,"error":"DOWNLOAD_TOO_LARGE","data":null}'),
    });
    final result =
        await TorboxProvider(dio: dio).resolveFile(_req(), apiKey: 'k');
    expect((result as DebridError).permanent, isTrue);
  });

  test('validateKey accepts a working key and flags a rejected one', () async {
    final ok = stubbedDio(_base, {
      '/v1/api/user/me': (_) => jsonBody('{"success":true,"data":{"id":1}}'),
    });
    expect(await TorboxProvider(dio: ok).validateKey('k'), isNull);

    final bad = stubbedDio(_base, {
      '/v1/api/user/me': (_) => jsonBody('{"success":false}', 401),
    });
    expect(await TorboxProvider(dio: bad).validateKey('k'),
        'Invalid TorBox API key');
  });
}

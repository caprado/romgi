import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/services/metadata/metadata_provider.dart';
import 'package:romgi/services/metadata/steamgriddb_provider.dart';

import '../debrid/debrid_test_utils.dart';

const _base = 'https://www.steamgriddb.com/api/v2';
const _search = '/api/v2/search/autocomplete/Celeste';

const _creds = {'apiKey': 'key'};

Future<MetadataResult> _fetch(
    Map<String, ResponseBody Function(RequestOptions)> routes) {
  final provider = SteamGridDbProvider(dio: stubbedDio(_base, routes));
  return provider.fetch(title: 'Celeste', platform: 'ps1', creds: _creds);
}

void main() {
  test('merges heroes then grids and caps the total at 6', () async {
    final result = await _fetch({
      _search: (_) => jsonBody(
          '{"success":true,"data":[{"id":123,"name":"Celeste"}]}'),
      '/api/v2/heroes/game/123': (_) => jsonBody('{"success":true,"data":['
          '{"url":"https://sgdb/hero1"},{"url":"https://sgdb/hero2"},'
          '{"url":"https://sgdb/hero3"},{"url":"https://sgdb/hero4"}]}'),
      '/api/v2/grids/game/123': (_) => jsonBody('{"success":true,"data":['
          '{"url":"https://sgdb/grid1"},{"url":"https://sgdb/grid2"},'
          '{"url":"https://sgdb/grid3"},{"url":"https://sgdb/grid4"}]}'),
    });
    final found = result as MetadataFound;
    expect(found.artworkUrls, hasLength(6));
    expect(found.artworkUrls.first, 'https://sgdb/hero1');
    expect(found.artworkUrls.last, 'https://sgdb/grid2');
    expect(found.description, isNull);
    expect(found.screenshotUrls, isEmpty);
  });

  test('prefers the exact name match over the first result', () async {
    final stub = StubAdapter({
      _search: (_) => jsonBody('{"success":true,"data":['
          '{"id":1,"name":"Celeste Classic"},{"id":2,"name":"celeste"}]}'),
      '/api/v2/heroes/game/2': (_) =>
          jsonBody('{"success":true,"data":[{"url":"https://sgdb/right"}]}'),
      '/api/v2/grids/game/2': (_) => jsonBody('{"success":true,"data":[]}'),
    });
    final dio = stubbedDio(_base, stub.routes)..httpClientAdapter = stub;
    final result = await SteamGridDbProvider(dio: dio)
        .fetch(title: 'Celeste', platform: 'ps1', creds: _creds);

    expect((result as MetadataFound).artworkUrls, ['https://sgdb/right']);
    expect(stub.calls.first.headers['Authorization'], 'Bearer key');
  });

  test('empty search results are a no-match', () async {
    final result = await _fetch({
      _search: (_) => jsonBody('{"success":true,"data":[]}'),
    });
    expect(result, isA<MetadataNoMatch>());
  });

  test('success:false envelope surfaces an error', () async {
    final result = await _fetch({
      _search: (_) =>
          jsonBody('{"success":false,"errors":["Bad request"]}', 400),
    });
    expect(result, isA<MetadataError>());
    expect((result as MetadataError).message, contains('Bad request'));
  });

  test('401 surfaces an auth error', () async {
    final result = await _fetch({
      _search: (_) => jsonBody('{"success":false}', 401),
    });
    expect((result as MetadataError).authError, isTrue);
  });

  test('validateCredentials accepts a working key and flags a rejected one',
      () async {
    final ok = stubbedDio(_base, {
      '/api/v2/search/autocomplete/mario': (_) =>
          jsonBody('{"success":true,"data":[]}'),
    });
    expect(
      await SteamGridDbProvider(dio: ok).validateCredentials(_creds),
      isNull,
    );

    final bad = stubbedDio(_base, {
      '/api/v2/search/autocomplete/mario': (_) =>
          jsonBody('{"success":false}', 401),
    });
    expect(
      await SteamGridDbProvider(dio: bad).validateCredentials(_creds),
      'Invalid SteamGridDB API key',
    );
  });
}

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/services/metadata/metadata_provider.dart';
import 'package:romgi/services/metadata/screenscraper_provider.dart';

import '../debrid/debrid_test_utils.dart';

const _base = 'https://api.screenscraper.fr/api2';
const _search = '/api2/jeuRecherche.php';
const _userInfo = '/api2/ssuserInfos.php';

const _creds = {'username': 'user', 'password': 'dummy-pass'};

String _jeu({
  String name = 'Chrono Cross',
  List<String>? synopsis,
  List<String>? medias,
}) {
  return '{"noms":[{"region":"us","text":"$name"}],'
      '"synopsis":[${(synopsis ?? const []).join(',')}],'
      '"medias":[${(medias ?? const []).join(',')}]}';
}

String _response(List<String> jeux) =>
    '{"response":{"jeux":[${jeux.join(',')}]}}';

Future<MetadataResult> _fetch(
  Map<String, ResponseBody Function(RequestOptions)> routes, {
  String title = 'Chrono Cross',
  Map<String, String> creds = _creds,
}) {
  final provider = ScreenScraperProvider(dio: stubbedDio(_base, routes));
  return provider.fetch(title: title, platform: 'ps1', creds: creds);
}

void main() {
  test('parses the english synopsis over the french one', () async {
    final result = await _fetch({
      _search: (_) => jsonBody(_response([
            _jeu(synopsis: [
              '{"langue":"fr","text":"texte francais"}',
              '{"langue":"en","text":"english text"}',
            ]),
          ])),
    });
    expect(result, isA<MetadataFound>());
    expect((result as MetadataFound).description, 'english text');
  });

  test('falls back to the first synopsis when there is no english one',
      () async {
    final result = await _fetch({
      _search: (_) => jsonBody(_response([
            _jeu(synopsis: ['{"langue":"fr","text":"texte francais"}']),
          ])),
    });
    expect((result as MetadataFound).description, 'texte francais');
  });

  test('collects ss and sstitle medias, capped at 8', () async {
    final medias = <String>[
      '{"type":"box-2D","url":"https://ss/box"}',
      '{"type":"sstitle","url":"https://ss/title"}',
      for (var i = 0; i < 10; i++) '{"type":"ss","url":"https://ss/shot$i"}',
      '{"type":"video","url":"https://ss/video"}',
    ];
    final result = await _fetch({
      _search: (_) => jsonBody(_response([_jeu(medias: medias)])),
    });
    final found = result as MetadataFound;
    expect(found.screenshotUrls, hasLength(8));
    expect(found.screenshotUrls.first, 'https://ss/title');
    expect(found.screenshotUrls, isNot(contains('https://ss/box')));
    expect(found.screenshotUrls, isNot(contains('https://ss/video')));
  });

  test('prefers the exact name match over the first result', () async {
    final result = await _fetch({
      _search: (_) => jsonBody(_response([
            _jeu(
              name: 'Chrono Cross Demo',
              synopsis: ['{"langue":"en","text":"demo"}'],
            ),
            _jeu(
              name: 'chrono cross',
              synopsis: ['{"langue":"en","text":"the real one"}'],
            ),
          ])),
    });
    expect((result as MetadataFound).description, 'the real one');
  });

  test('404 and empty jeux are no-match, not errors', () async {
    expect(
      await _fetch({_search: (_) => textBody('Erreur : Jeu non trouvé !', 404)}),
      isA<MetadataNoMatch>(),
    );
    expect(
      await _fetch({_search: (_) => jsonBody(_response([]))}),
      isA<MetadataNoMatch>(),
    );
  });

  test('plain-text login error with HTTP 200 is an auth error', () async {
    final result = await _fetch({
      _search: (_) =>
          textBody('Erreur de login : Vérifier vos identifiants !'),
    });
    expect(result, isA<MetadataError>());
    expect((result as MetadataError).authError, isTrue);
  });

  test('quota text response is an error but not an auth error', () async {
    final result = await _fetch({
      _search: (_) => textBody(
          "Votre quota de scrape est dépassé pour aujourd'hui !"),
    });
    final error = result as MetadataError;
    expect(error.authError, isFalse);
    expect(error.message, contains('quota'));
  });

  test('unmapped platform skips ScreenScraper as a no-match', () async {
    final provider = ScreenScraperProvider(dio: stubbedDio(_base, {}));
    final result = await provider.fetch(
      title: 'Game',
      platform: 'pip',
      creds: _creds,
    );
    expect(result, isA<MetadataNoMatch>());
  });

  test('devid params are omitted when no dev credentials are built in',
      () async {
    final stub = StubAdapter({
      _search: (_) => jsonBody(_response([_jeu()])),
    });
    final dio = stubbedDio(_base, stub.routes)..httpClientAdapter = stub;
    await ScreenScraperProvider(dio: dio)
        .fetch(title: 'Chrono Cross', platform: 'ps1', creds: _creds);

    final query = stub.calls.single.uri.queryParameters;
    expect(query.containsKey('devid'), isFalse);
    expect(query.containsKey('devpassword'), isFalse);
    expect(query['ssid'], 'user');
    expect(query['sspassword'], 'dummy-pass');
    expect(query['systemeid'], '57');
    expect(query['softname'], 'romgi');
  });

  test('devid params come from build-time credentials, not user input',
      () async {
    final stub = StubAdapter({
      _search: (_) => jsonBody(_response([_jeu()])),
    });
    final dio = stubbedDio(_base, stub.routes)..httpClientAdapter = stub;
    await ScreenScraperProvider(
      dio: dio,
      devId: 'dev',
      devPassword: 'dummy-devpass',
    ).fetch(
      title: 'Chrono Cross',
      platform: 'ps1',
      creds: {..._creds, 'devId': 'ignored', 'devPassword': 'ignored'},
    );

    final query = stub.calls.single.uri.queryParameters;
    expect(query['devid'], 'dev');
    expect(query['devpassword'], 'dummy-devpass');
  });

  test('validateCredentials accepts a working login and flags a bad one',
      () async {
    final ok = stubbedDio(_base, {
      _userInfo: (_) => jsonBody('{"response":{"ssuser":{"id":"user"}}}'),
    });
    expect(
      await ScreenScraperProvider(dio: ok).validateCredentials(_creds),
      isNull,
    );

    final bad = stubbedDio(_base, {
      _userInfo: (_) => textBody('Erreur de login : identifiants invalides'),
    });
    expect(
      await ScreenScraperProvider(dio: bad).validateCredentials(_creds),
      'Invalid ScreenScraper credentials',
    );
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/models/models.dart';
import 'package:romgi/services/database_service.dart';
import 'package:romgi/services/game_metadata_service.dart';
import 'package:romgi/services/metadata/metadata_provider.dart';
import 'package:romgi/services/metadata/metadata_registry.dart';

import '../debrid/debrid_test_utils.dart';

class FakeDatabaseService extends Fake implements DatabaseService {
  final Map<String, ({String payload, DateTime fetchedAt, bool noMatch})> rows =
      {};
  int puts = 0;

  @override
  Future<({String payload, DateTime fetchedAt, bool noMatch})?>
      getGameMetadataCache(String key) async => rows[key];

  @override
  Future<void> putGameMetadataCache({
    required String key,
    required String payload,
    required bool noMatch,
  }) async {
    puts++;
    rows[key] = (payload: payload, fetchedAt: DateTime.now(), noMatch: noMatch);
  }
}

class FakeMetadataProvider extends GameMetadataProvider {
  final String id;
  final MetadataResult Function() result;
  int calls = 0;

  FakeMetadataProvider(this.result, {this.id = 'fake'});

  @override
  MetadataProviderInfo get info => MetadataProviderInfo(id: id, name: id);

  @override
  List<CredentialField> get credentialFields => const [
        CredentialField(key: 'apiKey', label: 'API key'),
        CredentialField(key: 'extra', label: 'Extra', optional: true),
      ];

  @override
  Future<String?> validateCredentials(Map<String, String> creds) async => null;

  @override
  Future<MetadataResult> fetch({
    required String title,
    required String platform,
    required Map<String, String> creds,
  }) async {
    calls++;
    return result();
  }
}

RomEntry _entry(String title, {String platform = 'ps1'}) => RomEntry(
      slug: title.toLowerCase().replaceAll(' ', '-'),
      title: title,
      platform: platform,
      regions: const ['us'],
      links: const [],
    );

GameMetadataService _service(
  List<FakeMetadataProvider> providers, {
  FakeDatabaseService? db,
  Map<String, String>? store,
}) =>
    GameMetadataService(
      db: db ?? FakeDatabaseService(),
      registry: MetadataProviderRegistry(providers: providers),
      storage: InMemorySecureStorage(store ?? {}),
    );

Future<void> _configure(GameMetadataService service, String providerId) =>
    service.setCredentials(
      providerId: providerId,
      credentials: {'apiKey': 'k'},
    );

void main() {
  test('unconfigured returns null without calling providers', () async {
    final provider = FakeMetadataProvider(
        () => const MetadataFound(description: 'desc'));
    final service = _service([provider]);

    expect(await service.getMetadata(_entry('Game')), isNull);
    expect(provider.calls, 0);
  });

  test('fetches, caches and returns merged metadata', () async {
    final db = FakeDatabaseService();
    final provider = FakeMetadataProvider(() => const MetadataFound(
          description: 'desc',
          screenshotUrls: ['https://ss/1'],
        ));
    final service = _service([provider], db: db);
    await _configure(service, 'fake');

    final metadata = await service.getMetadata(_entry('Game (USA)'));
    expect(metadata!.description, 'desc');
    expect(metadata.screenshotUrls, ['https://ss/1']);
    expect(db.rows['ps1|game']!.noMatch, isFalse);
  });

  test('cache hit within the TTL skips provider calls', () async {
    final db = FakeDatabaseService();
    db.rows['ps1|game'] = (
      payload: jsonEncode(const GameMetadata(description: 'cached').toJson()),
      fetchedAt: DateTime.now().subtract(const Duration(days: 13)),
      noMatch: false,
    );
    final provider = FakeMetadataProvider(
        () => const MetadataFound(description: 'fresh'));
    final service = _service([provider], db: db);
    await _configure(service, 'fake');

    final metadata = await service.getMetadata(_entry('Game'));
    expect(metadata!.description, 'cached');
    expect(provider.calls, 0);
  });

  test('expired cache refetches', () async {
    final db = FakeDatabaseService();
    db.rows['ps1|game'] = (
      payload: jsonEncode(const GameMetadata(description: 'stale').toJson()),
      fetchedAt: DateTime.now().subtract(const Duration(days: 15)),
      noMatch: false,
    );
    final provider = FakeMetadataProvider(
        () => const MetadataFound(description: 'fresh'));
    final service = _service([provider], db: db);
    await _configure(service, 'fake');

    final metadata = await service.getMetadata(_entry('Game'));
    expect(metadata!.description, 'fresh');
    expect(provider.calls, 1);
    expect(db.puts, 1);
  });

  test('no-match is cached and honoured with the shorter TTL', () async {
    final db = FakeDatabaseService();
    final provider = FakeMetadataProvider(() => const MetadataNoMatch());
    final service = _service([provider], db: db);
    await _configure(service, 'fake');

    expect(await service.getMetadata(_entry('Obscure Game')), isNull);
    expect(db.rows['ps1|obscure game']!.noMatch, isTrue);

    expect(await service.getMetadata(_entry('Obscure Game')), isNull);
    expect(provider.calls, 1);

    db.rows['ps1|obscure game'] = (
      payload: db.rows['ps1|obscure game']!.payload,
      fetchedAt: DateTime.now().subtract(const Duration(days: 4)),
      noMatch: true,
    );
    expect(await service.getMetadata(_entry('Obscure Game')), isNull);
    expect(provider.calls, 2);
  });

  test('errors are not cached', () async {
    final db = FakeDatabaseService();
    final provider = FakeMetadataProvider(
        () => const MetadataError('down', authError: true));
    final service = _service([provider], db: db);
    await _configure(service, 'fake');

    expect(await service.getMetadata(_entry('Game')), isNull);
    expect(db.rows, isEmpty);
    expect(db.puts, 0);
  });

  test('one provider failing still returns the other one\'s data', () async {
    final broken =
        FakeMetadataProvider(() => const MetadataError('down'), id: 'a');
    final working = FakeMetadataProvider(
      () => const MetadataFound(artworkUrls: ['https://sgdb/1']),
      id: 'b',
    );
    final service = _service([broken, working]);
    await _configure(service, 'a');
    await _configure(service, 'b');

    final metadata = await service.getMetadata(_entry('Game'));
    expect(metadata!.artworkUrls, ['https://sgdb/1']);
    expect(metadata.description, isNull);
  });

  test('only configured providers are queried', () async {
    final configured = FakeMetadataProvider(
      () => const MetadataFound(description: 'desc'),
      id: 'a',
    );
    final unconfigured = FakeMetadataProvider(
      () => const MetadataFound(artworkUrls: ['x']),
      id: 'b',
    );
    final service = _service([configured, unconfigured]);
    await _configure(service, 'a');

    final metadata = await service.getMetadata(_entry('Game'));
    expect(metadata!.description, 'desc');
    expect(metadata.artworkUrls, isEmpty);
    expect(unconfigured.calls, 0);
  });

  test('multi-disc entries share one cache key and one fetch', () async {
    final db = FakeDatabaseService();
    final provider = FakeMetadataProvider(
        () => const MetadataFound(description: 'desc'));
    final service = _service([provider], db: db);
    await _configure(service, 'fake');

    await service.getMetadata(_entry('Game (Disc 1)'));
    await service.getMetadata(_entry('Game (Disc 2)'));
    expect(provider.calls, 1);
    expect(db.rows.keys, ['ps1|game']);
  });

  test('title cleaning strips parenthetical and bracketed groups', () {
    expect(GameMetadataService.cleanTitle('Game (USA) [!]'), 'Game');
    expect(GameMetadataService.cleanTitle('Game (Disc 1) (USA, Europe)'),
        'Game');
    expect(GameMetadataService.cleanTitle('Game [b1] - Special (Rev A)'),
        'Game - Special');
    expect(GameMetadataService.cleanTitle('Plain Title'), 'Plain Title');
  });

  test('credentials round-trip through secure storage', () async {
    final store = <String, String>{};
    final provider = FakeMetadataProvider(() => const MetadataNoMatch());
    final service = _service([provider], store: store);

    expect(await service.isConfigured('fake'), isFalse);
    expect(await service.anyConfigured(), isFalse);

    await service.setCredentials(
      providerId: 'fake',
      credentials: {'apiKey': ' k ', 'extra': ''},
    );
    expect(await service.isConfigured('fake'), isTrue);
    expect(await service.anyConfigured(), isTrue);
    expect(
      jsonDecode(store['metadata.credentials.v1.fake']!),
      {'apiKey': 'k'},
    );

    final reloaded = _service([provider], store: store);
    expect(await reloaded.isConfigured('fake'), isTrue);

    await service.clearCredentials('fake');
    expect(await service.isConfigured('fake'), isFalse);
    expect(store.containsKey('metadata.credentials.v1.fake'), isFalse);
  });

  test('missing required fields leave the provider unconfigured', () async {
    final provider = FakeMetadataProvider(() => const MetadataNoMatch());
    final service = _service([provider]);
    await service.setCredentials(
      providerId: 'fake',
      credentials: {'extra': 'only-optional'},
    );
    expect(await service.isConfigured('fake'), isFalse);
    expect(await service.testConnection('fake'), 'No credentials set');
  });
}

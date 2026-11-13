import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/models/models.dart';
import 'package:romgi/services/debrid/debrid_provider.dart';
import 'package:romgi/services/debrid/debrid_registry.dart';
import 'package:romgi/services/debrid_service.dart';
import 'package:romgi/services/rom_database_service.dart';

import 'debrid_test_utils.dart';

const _hash = 'abcdef0123456789abcdef0123456789abcdef01';

class _FakeProvider implements DebridProvider {
  final List<DebridResult> script;
  final String id;
  int calls = 0;
  DebridFileRequest? lastReq;

  _FakeProvider(this.script, {this.id = 'fake'});

  @override
  DebridProviderInfo get info => DebridProviderInfo(id: id, name: 'Fake $id');

  @override
  bool isConfigured(String? apiKey) => apiKey != null && apiKey.isNotEmpty;

  @override
  Future<String?> validateKey(String apiKey) async => null;

  @override
  Future<DebridResult> resolveFile(DebridFileRequest req,
      {required String apiKey}) async {
    lastReq = req;
    final result = script[calls < script.length ? calls : script.length - 1];
    calls++;
    return result;
  }
}

class _FakeRomDb extends RomDatabaseService {
  final TorrentMetadata? meta;
  _FakeRomDb(this.meta);

  @override
  Future<TorrentMetadata?> getTorrentMetadata(String infohash) async => meta;
}

DownloadLink _torrentLink() => const DownloadLink(
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
      torrentFileIndex: 0,
    );

DebridService _service(_FakeProvider provider, {TorrentMetadata? meta}) =>
    DebridService(
      romDb: _FakeRomDb(meta),
      registry: DebridProviderRegistry(providers: [provider]),
      storage: InMemorySecureStorage({}),
    );

void main() {
  test('ready result becomes a plain HTTP link', () async {
    final provider = _FakeProvider([const DebridReady('https://cdn/x.iso')]);
    final service = _service(provider);
    await service.setCredentials(providerId: 'fake', apiKey: 'k');

    final link = (await service.resolveTorrentLink(_torrentLink())).link;
    expect(link, isNotNull);
    expect(link!.isTorrent, isFalse);
    expect(link.url, 'https://cdn/x.iso');
    expect(link.debridResolved, isTrue);
    expect(link.torrentInfohash, _hash);
    expect(link.filename, 'game.iso'); // preserved for extraction/naming
  });

  test('caching then ready — polls and fires onCaching', () async {
    final provider = _FakeProvider([
      const DebridCaching(progress: 0.5),
      const DebridReady('https://cdn/y.iso'),
    ]);
    final service = _service(provider);
    await service.setCredentials(providerId: 'fake', apiKey: 'k');

    var cachingSeen = 0;
    final result = await service.resolveTorrentLink(
      _torrentLink(),
      pollInterval: const Duration(milliseconds: 1),
      onCaching: (_) => cachingSeen++,
    );
    expect(result.link?.url, 'https://cdn/y.iso');
    expect(cachingSeen, 1);
    expect(provider.calls, 2);
  });

  test('not cached fails with a reason', () async {
    final service = _service(_FakeProvider([const DebridNotCached()]));
    await service.setCredentials(providerId: 'fake', apiKey: 'k');
    final result = await service.resolveTorrentLink(_torrentLink());
    expect(result.link, isNull);
    expect(result.failure, contains('Fake fake'));
  });

  test('auth error fails with its message without polling', () async {
    final provider =
        _FakeProvider([const DebridError('bad key', authError: true)]);
    final service = _service(provider);
    await service.setCredentials(providerId: 'fake', apiKey: 'k');

    final result = await service.resolveTorrentLink(_torrentLink());
    expect(result.link, isNull);
    expect(result.failure, 'bad key');
    expect(provider.calls, 1);
  });

  test('gives up when caching stops making progress', () async {
    final provider = _FakeProvider([const DebridCaching(progress: 0.2)]);
    final service = _service(provider);
    await service.setCredentials(providerId: 'fake', apiKey: 'k');

    final result = await service.resolveTorrentLink(
      _torrentLink(),
      pollInterval: const Duration(milliseconds: 1),
      maxPollInterval: const Duration(milliseconds: 1),
      stallTimeout: const Duration(milliseconds: 20),
    );
    expect(result.link, isNull);
    expect(result.failure, contains('stopped making progress'));
  });

  test('keeps waiting past the stall window while progress moves', () async {
    final provider = _FakeProvider([
      for (var i = 1; i <= 15; i++) DebridCaching(progress: i / 20),
      const DebridReady('https://cdn/slow.iso'),
    ]);
    final service = _service(provider);
    await service.setCredentials(providerId: 'fake', apiKey: 'k');

    final result = await service.resolveTorrentLink(
      _torrentLink(),
      pollInterval: const Duration(milliseconds: 5),
      maxPollInterval: const Duration(milliseconds: 5),
      stallTimeout: const Duration(milliseconds: 30),
    );
    expect(result.link?.url, 'https://cdn/slow.iso');
    expect(provider.calls, 16);
  });

  test('synthesizes a magnet when the catalog has none', () async {
    final provider = _FakeProvider([const DebridReady('https://cdn/x')]);
    final service = _service(provider); // meta null
    await service.setCredentials(providerId: 'fake', apiKey: 'k');

    await service.resolveTorrentLink(_torrentLink());
    expect(provider.lastReq!.magnet, contains('xt=urn:btih:$_hash'));
  });

  test('prefers the catalog magnet when present', () async {
    final provider = _FakeProvider([const DebridReady('https://cdn/x')]);
    final service = _service(
      provider,
      meta: const TorrentMetadata(
          infohash: _hash, magnet: 'magnet:?xt=urn:btih:$_hash&stored=1'),
    );
    await service.setCredentials(providerId: 'fake', apiKey: 'k');

    await service.resolveTorrentLink(_torrentLink());
    expect(provider.lastReq!.magnet, contains('stored=1'));
  });

  test('credentials round-trip and clear', () async {
    final service = _service(_FakeProvider([const DebridNotCached()]));
    expect(await service.isConfigured(), isFalse);
    await service.setCredentials(providerId: 'fake', apiKey: 'k');
    expect(await service.isConfigured(), isTrue);
    await service.clearCredentials();
    expect(await service.isConfigured(), isFalse);
  });

  test('fails when no debrid credentials are set', () async {
    final service = _service(_FakeProvider([const DebridReady('x')]));
    final result = await service.resolveTorrentLink(_torrentLink());
    expect(result.link, isNull);
    expect(result.failure, 'No Fake fake API key saved');
  });

  test('cancellation aborts the poll promptly', () async {
    final provider = _FakeProvider([
      const DebridCaching(),
      const DebridCaching(),
      const DebridReady('https://cdn/late.iso'),
    ]);
    final service = _service(provider);
    await service.setCredentials(providerId: 'fake', apiKey: 'k');

    var canceled = false;
    final link = await service.resolveTorrentLink(
      _torrentLink(),
      pollInterval: const Duration(milliseconds: 1),
      onCaching: (_) => canceled = true, // cancel mid-poll
      isCancelled: () => canceled,
    );
    expect(link.link, isNull);
    expect(link.failure, isNull);
    expect(provider.calls, 1); // no further provider calls after cancel
  });

  test('cancellation before the first provider call makes none', () async {
    final provider = _FakeProvider([const DebridReady('https://cdn/x')]);
    final service = _service(provider);
    await service.setCredentials(providerId: 'fake', apiKey: 'k');

    final link = await service.resolveTorrentLink(
      _torrentLink(),
      isCancelled: () => true,
    );
    expect(link.link, isNull);
    expect(link.failure, isNull);
    expect(provider.calls, 0);
  });

  test('permanent error aborts the poll without waiting', () async {
    final provider = _FakeProvider(
        [const DebridError('Active torrent limit', permanent: true)]);
    final service = _service(provider);
    await service.setCredentials(providerId: 'fake', apiKey: 'k');

    final link = await service.resolveTorrentLink(
      _torrentLink(),
      pollInterval: const Duration(milliseconds: 1),
    );
    expect(link.link, isNull);
    expect(link.failure, 'Active torrent limit');
    expect(provider.calls, 1); // terminal — no retry loop
  });

  test('retryable error keeps polling until it resolves', () async {
    final provider = _FakeProvider([
      const DebridError('blip'),
      const DebridReady('https://cdn/z.iso'),
    ]);
    final service = _service(provider);
    await service.setCredentials(providerId: 'fake', apiKey: 'k');

    final result = await service.resolveTorrentLink(
      _torrentLink(),
      pollInterval: const Duration(milliseconds: 1),
    );
    expect(result.link?.url, 'https://cdn/z.iso');
    expect(provider.calls, 2);
  });

  test('credentials are stored per provider and follow the selection',
      () async {
    final a = _FakeProvider([const DebridReady('https://cdn/a')], id: 'a');
    final b = _FakeProvider([const DebridReady('https://cdn/b')], id: 'b');
    final service = DebridService(
      romDb: _FakeRomDb(null),
      registry: DebridProviderRegistry(providers: [a, b]),
      storage: InMemorySecureStorage({}),
    );
    await service.setCredentials(providerId: 'a', apiKey: 'key-a');

    service.getSelectedProviderId = () => 'a';
    expect(await service.isConfigured(), isTrue);
    expect((await service.resolveTorrentLink(_torrentLink())).link?.url,
        'https://cdn/a');

    service.getSelectedProviderId = () => 'b';
    expect(await service.isConfigured(), isFalse);
    expect(await service.testConnection(), 'No API key set');
    expect((await service.resolveTorrentLink(_torrentLink())).link, isNull);
    expect(b.calls, 0);

    service.getSelectedProviderId = () => 'a';
    expect(await service.isConfigured(), isTrue);
  });

  test('legacy single-slot credentials migrate to a per-provider slot',
      () async {
    final store = <String, String>{
      'debrid.credentials.v1': '{"providerId":"fake","apiKey":"legacy-key"}',
    };
    final service = DebridService(
      romDb: _FakeRomDb(null),
      registry:
          DebridProviderRegistry(providers: [_FakeProvider(const [])]),
      storage: InMemorySecureStorage(store),
    );
    expect(await service.isConfigured(), isTrue);
    expect(store.containsKey('debrid.credentials.v1'), isFalse);
    expect(store['debrid.credentials.v1.fake'], 'legacy-key');
  });
}

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
  int calls = 0;
  DebridFileRequest? lastReq;

  _FakeProvider(this.script);

  @override
  DebridProviderInfo get info =>
      const DebridProviderInfo(id: 'fake', name: 'Fake');

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

    final link = await service.resolveTorrentLink(_torrentLink());
    expect(link, isNotNull);
    expect(link!.isTorrent, isFalse);
    expect(link.url, 'https://cdn/x.iso');
    expect(link.torrentInfohash, isNull);
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
    final link = await service.resolveTorrentLink(
      _torrentLink(),
      pollInterval: const Duration(milliseconds: 1),
      onCaching: (_) => cachingSeen++,
    );
    expect(link?.url, 'https://cdn/y.iso');
    expect(cachingSeen, 1);
    expect(provider.calls, 2);
  });

  test('not cached returns null', () async {
    final service = _service(_FakeProvider([const DebridNotCached()]));
    await service.setCredentials(providerId: 'fake', apiKey: 'k');
    expect(await service.resolveTorrentLink(_torrentLink()), isNull);
  });

  test('auth error returns null without polling', () async {
    final provider =
        _FakeProvider([const DebridError('bad', authError: true)]);
    final service = _service(provider);
    await service.setCredentials(providerId: 'fake', apiKey: 'k');

    expect(await service.resolveTorrentLink(_torrentLink()), isNull);
    expect(provider.calls, 1);
  });

  test('times out to null while stuck caching', () async {
    final provider = _FakeProvider([const DebridCaching()]);
    final service = _service(provider);
    await service.setCredentials(providerId: 'fake', apiKey: 'k');

    final link = await service.resolveTorrentLink(
      _torrentLink(),
      pollInterval: const Duration(milliseconds: 1),
      overallTimeout: const Duration(milliseconds: 5),
    );
    expect(link, isNull);
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

  test('returns null when no debrid credentials are set', () async {
    final service = _service(_FakeProvider([const DebridReady('x')]));
    expect(await service.resolveTorrentLink(_torrentLink()), isNull);
  });
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/services/torrent_service.dart';
import 'package:romgi/torrent/torrent_api.g.dart';

class _FakeHostApi extends TorrentHostApi {
  TorrentSettings? lastStart;
  TorrentSettings? lastUpdate;
  AddTorrentRequest? lastAdd;
  final List<String> canceled = [];
  bool pausedAll = false;
  bool resumedAll = false;
  List<TorrentProgress> snapshot = const [];
  String addReturn = 'aabbccddeeff00112233445566778899aabbccdd';

  @override
  Future<void> start(TorrentSettings settings) async {
    lastStart = settings;
  }

  @override
  Future<void> updateSettings(TorrentSettings settings) async {
    lastUpdate = settings;
  }

  @override
  Future<String> addTorrent(AddTorrentRequest request) async {
    lastAdd = request;
    return addReturn;
  }

  @override
  Future<void> cancel(String infohash) async {
    canceled.add(infohash);
  }

  @override
  Future<void> pauseAll() async {
    pausedAll = true;
  }

  @override
  Future<void> resumeAll() async {
    resumedAll = true;
  }

  @override
  Future<List<TorrentProgress>> listAll() async => snapshot;
}

TorrentService _makeService(_FakeHostApi fake) => TorrentService(
      api: fake,
      savePathResolver: () async => '/tmp/romgi-torrents',
    );

TorrentProgress _progress(String infohash, {int peers = 0}) {
  return TorrentProgress(
    infohash: infohash,
    name: 'pack',
    state: 'downloading',
    totalSize: 1000,
    bytesDownloaded: 500,
    downloadRate: 100,
    uploadRate: 0,
    peers: peers,
    seeds: 0,
    error: '',
    files: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('lifecycle', () {
    test('start forwards settings to the backend exactly once', () async {
      final fake = _FakeHostApi();
      final svc = _makeService(fake);
      await svc.start(seedingEnabled: true);
      await svc.start(seedingEnabled: true); // second call is a no-op (start)
      expect(fake.lastStart, isNotNull);
      expect(fake.lastStart!.seedingEnabled, isTrue);
      // second call should have updated settings, not re-started
      expect(fake.lastUpdate, isNotNull);
    });

    test('updateSeeding pushes the new flag through updateSettings', () async {
      final fake = _FakeHostApi();
      final svc = _makeService(fake);
      await svc.start(seedingEnabled: true);
      await svc.updateSeeding(false);
      expect(fake.lastUpdate?.seedingEnabled, isFalse);
    });
  });

  group('addTorrent', () {
    test('rejects when the runtime has not been started', () async {
      final svc = _makeService(_FakeHostApi());
      expect(
        () => svc.addTorrent(magnet: 'magnet:?xt=urn:btih:00'),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects when neither magnet nor torrentBytes is provided', () async {
      final fake = _FakeHostApi();
      final svc = _makeService(fake);
      await svc.start(seedingEnabled: true);
      expect(
        () => svc.addTorrent(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('forwards magnet + fileIndices and returns infohash', () async {
      final fake = _FakeHostApi();
      final svc = _makeService(fake);
      await svc.start(seedingEnabled: true);
      final ih = await svc.addTorrent(
        magnet: 'magnet:?xt=urn:btih:00',
        fileIndices: const [1, 4],
      );
      expect(ih, fake.addReturn);
      expect(fake.lastAdd?.magnet, 'magnet:?xt=urn:btih:00');
      expect(fake.lastAdd?.fileIndices, [1, 4]);
    });

    test('forwards torrentBytes when no magnet is set', () async {
      final fake = _FakeHostApi();
      final svc = _makeService(fake);
      await svc.start(seedingEnabled: true);
      await svc.addTorrent(
        torrentBytes: const [1, 2, 3, 4],
        fileIndices: const [],
      );
      expect(fake.lastAdd?.torrentBytes, isA<Uint8List>());
      expect(fake.lastAdd?.torrentBytes, [1, 2, 3, 4]);
    });
  });

  group('progress + error streams', () {
    test('onProgress fans out to the broadcast stream and caches latest',
        () async {
      final fake = _FakeHostApi();
      final svc = _makeService(fake);
      await svc.start(seedingEnabled: true);

      final emitted = <TorrentProgress>[];
      final sub = svc.progressStream.listen(emitted.add);
      addTearDown(sub.cancel);

      svc.onProgress(_progress('aa', peers: 5));
      svc.onProgress(_progress('aa', peers: 7));
      svc.onProgress(_progress('bb', peers: 1));

      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(3));
      expect(svc.latest['aa']!.peers, 7);
      expect(svc.latest['bb']!.peers, 1);
    });

    test('onError fans out on the error stream', () async {
      final fake = _FakeHostApi();
      final svc = _makeService(fake);
      await svc.start(seedingEnabled: true);

      final errors = <({String infohash, String error})>[];
      final sub = svc.errorStream.listen(errors.add);
      addTearDown(sub.cancel);

      svc.onError('aa', 'tracker timeout');
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
      expect(errors.first.infohash, 'aa');
      expect(errors.first.error, 'tracker timeout');
    });
  });

  group('cancel / pause / resume', () {
    test('cancel forwards and removes cached snapshot', () async {
      final fake = _FakeHostApi();
      final svc = _makeService(fake);
      await svc.start(seedingEnabled: true);
      svc.onProgress(_progress('aa'));
      expect(svc.latest, contains('aa'));

      await svc.cancel('aa');
      expect(fake.canceled, ['aa']);
      expect(svc.latest, isNot(contains('aa')));
    });

    test('pauseAll / resumeAll forward when started', () async {
      final fake = _FakeHostApi();
      final svc = _makeService(fake);
      await svc.start(seedingEnabled: true);
      await svc.pauseAll();
      await svc.resumeAll();
      expect(fake.pausedAll, isTrue);
      expect(fake.resumedAll, isTrue);
    });

    test('pauseAll / resumeAll are no-ops before start', () async {
      final fake = _FakeHostApi();
      final svc = _makeService(fake);
      await svc.pauseAll();
      await svc.resumeAll();
      expect(fake.pausedAll, isFalse);
      expect(fake.resumedAll, isFalse);
    });
  });
}

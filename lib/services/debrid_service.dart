import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/models.dart';
import 'debrid/debrid_provider.dart';
import 'debrid/debrid_registry.dart';
import 'rom_database_service.dart';
import 'torrent_magnet.dart';

class DebridService {
  DebridService({
    required RomDatabaseService romDb,
    DebridProviderRegistry? registry,
    FlutterSecureStorage? storage,
  })  : _romDb = romDb,
        _registry = registry ?? DebridProviderRegistry(),
        _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            ) {
    getSelectedProviderId = () => _registry.defaultProvider.info.id;
  }

  final RomDatabaseService _romDb;
  final DebridProviderRegistry _registry;
  final FlutterSecureStorage _storage;

  late String Function() getSelectedProviderId;

  static const String _legacyStorageKey = 'debrid.credentials.v1';

  static String _keyFor(String providerId) =>
      'debrid.credentials.v1.$providerId';

  final Map<String, String?> _cachedKeys = {};
  final Set<String> _loadedIds = {};
  bool _legacyChecked = false;

  DebridProviderRegistry get registry => _registry;

  Future<void> _migrateLegacy() async {
    if (_legacyChecked) return;
    _legacyChecked = true;
    try {
      final raw = await _storage.read(key: _legacyStorageKey);
      if (raw != null && raw.isNotEmpty) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final providerId = json['providerId'] as String? ?? '';
        final apiKey = json['apiKey'] as String? ?? '';
        if (providerId.isNotEmpty && apiKey.isNotEmpty) {
          await _storage.write(key: _keyFor(providerId), value: apiKey);
        }
        await _storage.delete(key: _legacyStorageKey);
      }
    } catch (_) {
      // Corrupt legacy blob — drop it.
    }
  }

  Future<String?> _readKey(String providerId) async {
    await _migrateLegacy();
    if (_loadedIds.contains(providerId)) return _cachedKeys[providerId];
    String? key;
    try {
      key = await _storage.read(key: _keyFor(providerId));
    } catch (_) {
      key = null;
    }
    _cachedKeys[providerId] = key;
    _loadedIds.add(providerId);
    return key;
  }

  Future<void> setCredentials({
    required String providerId,
    required String apiKey,
  }) async {
    await _migrateLegacy();
    final trimmed = apiKey.trim();
    await _storage.write(key: _keyFor(providerId), value: trimmed);
    _cachedKeys[providerId] = trimmed;
    _loadedIds.add(providerId);
  }

  Future<void> clearCredentials({String? providerId}) async {
    await _migrateLegacy();
    final id = providerId ?? getSelectedProviderId();
    await _storage.delete(key: _keyFor(id));
    _cachedKeys[id] = null;
    _loadedIds.add(id);
  }

  Future<bool> isConfigured({String? providerId}) async {
    final id = providerId ?? getSelectedProviderId();
    final provider = _registry.byId(id);
    if (provider == null) return false;
    return provider.isConfigured(await _readKey(id));
  }

  Future<String?> testConnection({String? providerId}) async {
    final id = providerId ?? getSelectedProviderId();
    final provider = _registry.byId(id);
    final key = provider == null ? null : await _readKey(id);
    if (provider == null || !provider.isConfigured(key)) {
      return 'No API key set';
    }
    return provider.validateKey(key!);
  }

  /// Polls until the provider has the file. Uncached torrents can take hours,
  /// so there is no overall deadline; it gives up only when caching stops
  /// making progress for [stallTimeout]. [DebridResolution.link] is null on
  /// failure or cancel, with [DebridResolution.failure] set on failure.
  Future<DebridResolution> resolveTorrentLink(
    DownloadLink link, {
    void Function(DebridCaching status)? onCaching,
    bool Function()? isCancelled,
    Duration stallTimeout = const Duration(minutes: 30),
    Duration pollInterval = const Duration(seconds: 2),
    Duration maxPollInterval = const Duration(seconds: 30),
  }) async {
    if (!link.isTorrent) return const DebridResolution.failed('Not a torrent link');

    final id = getSelectedProviderId();
    final provider = _registry.byId(id);
    if (provider == null) {
      return const DebridResolution.failed('No debrid provider selected');
    }
    final name = provider.info.name;
    final apiKey = await _readKey(id);
    if (!provider.isConfigured(apiKey)) {
      return DebridResolution.failed('No $name API key saved');
    }

    bool canceled() => isCancelled?.call() ?? false;
    if (canceled()) return const DebridResolution.canceled();

    final infohash = link.torrentInfohash!.toLowerCase();
    final req = DebridFileRequest(
      infohash: infohash,
      magnet: await magnetForInfohash(_romDb, infohash),
      fileIndex: link.torrentFileIndex ?? 0,
      filePath: link.torrentFilePath,
      expectedSize: link.size,
    );

    var lastProgress = -1.0;
    var lastProgressAt = DateTime.now();
    var delay = pollInterval;
    String? lastError;

    bool stalled() => DateTime.now().difference(lastProgressAt) > stallTimeout;

    while (true) {
      if (canceled()) return const DebridResolution.canceled();
      final result = await provider.resolveFile(req, apiKey: apiKey!);
      if (canceled()) return const DebridResolution.canceled();

      switch (result) {
        case DebridReady ready:
          return DebridResolution.ready(_toHttpLink(link, ready, name));
        case DebridNotCached():
          return DebridResolution.failed(
              "$name couldn't find this file in the torrent");
        case DebridCaching caching:
          onCaching?.call(caching);
          final progress = caching.progress ?? 0;
          if (progress > lastProgress) {
            lastProgress = progress;
            lastProgressAt = DateTime.now();
          } else if (stalled()) {
            return DebridResolution.failed(
                '$name stopped making progress caching this torrent');
          }
          await Future.delayed(caching.retryAfter ?? delay);
          delay = _nextDelay(delay, maxPollInterval);
        case DebridError error:
          if (error.authError || error.permanent) {
            return DebridResolution.failed(error.message);
          }
          lastError = error.message;
          if (stalled()) return DebridResolution.failed(lastError);
          await Future.delayed(
              error.rateLimited ? const Duration(seconds: 10) : delay);
          delay = _nextDelay(delay, maxPollInterval);
      }
    }
  }

  Duration _nextDelay(Duration current, Duration max) {
    final doubled = current * 2;
    return doubled > max ? max : doubled;
  }

  DownloadLink _toHttpLink(
    DownloadLink original,
    DebridReady ready,
    String providerName,
  ) {
    return original.copyWith(
      url: ready.url,
      host: providerName,
      requiresAuth: false,
      debridResolved: true,
      size: ready.size ?? original.size,
    );
  }
}

class DebridResolution {
  final DownloadLink? link;
  final String? failure;

  const DebridResolution.ready(DownloadLink this.link) : failure = null;
  const DebridResolution.failed(String this.failure) : link = null;
  const DebridResolution.canceled()
      : link = null,
        failure = null;
}

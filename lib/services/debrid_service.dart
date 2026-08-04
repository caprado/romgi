import 'dart:async';
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

  /// Cache-backed; returns false until [isConfigured] has run once.
  bool isConfiguredSync({String? providerId}) {
    final id = providerId ?? getSelectedProviderId();
    final provider = _registry.byId(id);
    if (provider == null) return false;
    if (!_loadedIds.contains(id)) {
      unawaited(_readKey(id));
      return false;
    }
    return provider.isConfigured(_cachedKeys[id]);
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

  Future<DownloadLink?> resolveTorrentLink(
    DownloadLink link, {
    void Function(DebridCaching status)? onCaching,
    bool Function()? isCancelled,
    Duration overallTimeout = const Duration(minutes: 3),
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    if (!link.isTorrent) return null;

    final id = getSelectedProviderId();
    final provider = _registry.byId(id);
    if (provider == null) return null;
    final apiKey = await _readKey(id);
    if (!provider.isConfigured(apiKey)) return null;

    bool cancelled() => isCancelled?.call() ?? false;
    if (cancelled()) return null;

    final infohash = link.torrentInfohash!.toLowerCase();
    final req = DebridFileRequest(
      infohash: infohash,
      magnet: await magnetForInfohash(_romDb, infohash),
      fileIndex: link.torrentFileIndex ?? 0,
      filePath: link.torrentFilePath,
      expectedSize: link.size,
    );

    final deadline = DateTime.now().add(overallTimeout);
    const maxDelay = Duration(seconds: 15);
    var delay = pollInterval;

    while (true) {
      if (cancelled()) return null;
      final result = await provider.resolveFile(req, apiKey: apiKey!);
      if (cancelled()) return null;

      switch (result) {
        case DebridReady ready:
          return _toHttpLink(link, ready, provider.info.name);
        case DebridNotCached():
          return null;
        case DebridCaching caching:
          onCaching?.call(caching);
          if (DateTime.now().isAfter(deadline)) return null;
          await Future.delayed(caching.retryAfter ?? delay);
          delay = _nextDelay(delay, maxDelay);
        case DebridError error:
          if (error.authError || error.permanent) {
            return null; // bad key or terminal error — polling won't help
          }
          if (DateTime.now().isAfter(deadline)) return null;
          await Future.delayed(
              error.rateLimited ? const Duration(seconds: 10) : delay);
          delay = _nextDelay(delay, maxDelay);
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

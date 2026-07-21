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
            );

  final RomDatabaseService _romDb;
  final DebridProviderRegistry _registry;
  final FlutterSecureStorage _storage;

  static const String _storageKey = 'debrid.credentials.v1';

  _Credentials? _cached;
  bool _loaded = false;

  DebridProviderRegistry get registry => _registry;

  Future<void> setCredentials({
    required String providerId,
    required String apiKey,
  }) async {
    final creds = _Credentials(providerId: providerId, apiKey: apiKey.trim());
    await _storage.write(key: _storageKey, value: jsonEncode(creds.toJson()));
    _cached = creds;
    _loaded = true;
  }

  Future<void> clearCredentials() async {
    await _storage.delete(key: _storageKey);
    _cached = null;
    _loaded = true;
  }

  Future<_Credentials?> _readCredentials() async {
    if (_loaded) return _cached;
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw != null && raw.isNotEmpty) {
        _cached = _Credentials.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      _cached = null;
    }
    _loaded = true;
    return _cached;
  }

  Future<String?> configuredProviderId() async =>
      (await _readCredentials())?.providerId;

  Future<bool> isConfigured() async {
    final creds = await _readCredentials();
    final provider = _registry.byId(creds?.providerId);
    return provider != null && provider.isConfigured(creds!.apiKey);
  }

  Future<String?> testConnection() async {
    final creds = await _readCredentials();
    final provider = _registry.byId(creds?.providerId);
    if (provider == null || creds == null || !provider.isConfigured(creds.apiKey)) {
      return 'No API key set';
    }
    return provider.validateKey(creds.apiKey);
  }

  Future<DownloadLink?> resolveTorrentLink(
    DownloadLink link, {
    void Function(DebridCaching status)? onCaching,
    Duration overallTimeout = const Duration(minutes: 3),
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    if (!link.isTorrent) return null;

    final creds = await _readCredentials();
    final provider = _registry.byId(creds?.providerId);
    if (provider == null || creds == null || !provider.isConfigured(creds.apiKey)) {
      return null;
    }

    final infohash = link.torrentInfohash!.toLowerCase();
    final req = DebridFileRequest(
      infohash: infohash,
      magnet: await _magnetFor(link, infohash),
      fileIndex: link.torrentFileIndex ?? 0,
      filePath: link.torrentFilePath,
      expectedSize: link.size,
    );

    final deadline = DateTime.now().add(overallTimeout);
    const maxDelay = Duration(seconds: 15);
    var delay = pollInterval;

    while (true) {
      final result = await provider.resolveFile(req, apiKey: creds.apiKey);

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
          if (error.authError) return null; // bad key — polling won't help
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

  Future<String> _magnetFor(DownloadLink link, String infohash) async {
    final meta = await _romDb.getTorrentMetadata(infohash);
    final stored = meta?.magnet;
    if (stored != null && stored.isNotEmpty) return stored;
    return buildMagnetUri(infohash, trackers: meta?.trackers);
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
      clearTorrentFields: true,
      size: ready.size ?? original.size,
    );
  }
}

class _Credentials {
  final String providerId;
  final String apiKey;

  const _Credentials({required this.providerId, required this.apiKey});

  Map<String, dynamic> toJson() => {'providerId': providerId, 'apiKey': apiKey};

  factory _Credentials.fromJson(Map<String, dynamic> json) => _Credentials(
    providerId: json['providerId'] as String? ?? '',
    apiKey: json['apiKey'] as String? ?? '',
  );
}

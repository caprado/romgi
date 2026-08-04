import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/models.dart';
import 'database_service.dart';
import 'metadata/metadata_provider.dart';
import 'metadata/metadata_registry.dart';

class GameMetadataService {
  GameMetadataService({
    required DatabaseService db,
    MetadataProviderRegistry? registry,
    FlutterSecureStorage? storage,
  })  : _db = db,
        _registry = registry ?? MetadataProviderRegistry(),
        _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final DatabaseService _db;
  final MetadataProviderRegistry _registry;
  final FlutterSecureStorage _storage;

  static const Duration _hitTtl = Duration(days: 14);
  static const Duration _missTtl = Duration(days: 3);

  static String _keyFor(String providerId) =>
      'metadata.credentials.v1.$providerId';

  final Map<String, Map<String, String>?> _cachedCreds = {};
  final Set<String> _loadedIds = {};

  MetadataProviderRegistry get registry => _registry;

  Future<Map<String, String>?> _readCreds(String providerId) async {
    if (_loadedIds.contains(providerId)) return _cachedCreds[providerId];
    Map<String, String>? creds;
    try {
      final raw = await _storage.read(key: _keyFor(providerId));
      if (raw != null && raw.isNotEmpty) {
        creds = (jsonDecode(raw) as Map<String, dynamic>)
            .map((key, value) => MapEntry(key, value.toString()));
      }
    } catch (_) {
      creds = null;
    }
    _cachedCreds[providerId] = creds;
    _loadedIds.add(providerId);
    return creds;
  }

  Future<void> setCredentials({
    required String providerId,
    required Map<String, String> credentials,
  }) async {
    final trimmed = {
      for (final entry in credentials.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
    };
    await _storage.write(key: _keyFor(providerId), value: jsonEncode(trimmed));
    _cachedCreds[providerId] = trimmed;
    _loadedIds.add(providerId);
  }

  Future<void> clearCredentials(String providerId) async {
    await _storage.delete(key: _keyFor(providerId));
    _cachedCreds[providerId] = null;
    _loadedIds.add(providerId);
  }

  Future<bool> isConfigured(String providerId) async {
    final provider = _registry.byId(providerId);
    if (provider == null) return false;
    return provider.isConfigured(await _readCreds(providerId));
  }

  Future<bool> anyConfigured() async {
    for (final provider in _registry.providers) {
      if (await isConfigured(provider.info.id)) return true;
    }
    return false;
  }

  Future<String?> testConnection(String providerId) async {
    final provider = _registry.byId(providerId);
    final creds = provider == null ? null : await _readCreds(providerId);
    if (provider == null || !provider.isConfigured(creds)) {
      return 'No credentials set';
    }
    return provider.validateCredentials(creds!);
  }

  static String cleanTitle(String title) => title
      .replaceAll(RegExp(r'\s*[\(\[][^)\]]*[\)\]]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<GameMetadata?> getMetadata(RomEntry entry) async {
    final configured = <GameMetadataProvider, Map<String, String>>{};
    for (final provider in _registry.providers) {
      final creds = await _readCreds(provider.info.id);
      if (provider.isConfigured(creds)) configured[provider] = creds!;
    }
    if (configured.isEmpty) return null;

    final title = cleanTitle(entry.title);
    if (title.isEmpty) return null;
    final cacheKey = '${entry.platform}|${title.toLowerCase()}';

    final cached = await _db.getGameMetadataCache(cacheKey);
    if (cached != null) {
      final ttl = cached.noMatch ? _missTtl : _hitTtl;
      if (DateTime.now().difference(cached.fetchedAt) < ttl) {
        if (cached.noMatch) return null;
        try {
          return GameMetadata.fromJson(
              jsonDecode(cached.payload) as Map<String, dynamic>);
        } catch (_) {}
      }
    }

    String? description;
    final screenshots = <String>[];
    final artwork = <String>[];
    var anyAnswered = false;

    for (final providerEntry in configured.entries) {
      try {
        final result = await providerEntry.key.fetch(
          title: title,
          platform: entry.platform,
          creds: providerEntry.value,
        );
        switch (result) {
          case MetadataFound found:
            anyAnswered = true;
            description ??= found.description;
            screenshots.addAll(found.screenshotUrls);
            artwork.addAll(found.artworkUrls);
          case MetadataNoMatch():
            anyAnswered = true;
          case MetadataError():
            break;
        }
      } catch (_) {}
    }
    if (!anyAnswered) return null;

    final metadata = GameMetadata(
      description: description,
      screenshotUrls: screenshots,
      artworkUrls: artwork,
    );
    await _db.putGameMetadataCache(
      key: cacheKey,
      payload: jsonEncode(metadata.toJson()),
      noMatch: metadata.isEmpty,
    );
    return metadata.isEmpty ? null : metadata;
  }
}

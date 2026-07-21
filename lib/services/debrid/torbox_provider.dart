import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import 'debrid_provider.dart';

/// TorBox (https://torbox.app) debrid provider.
///
/// Flow: create-or-get the torrent from its magnet, poll `mylist` for cache
/// state, then `requestdl` for a direct CDN link (valid ~3h). Auth is a bearer
/// API key from the TorBox settings page. Every response is wrapped as
/// `{success, detail, data}`.
class TorboxProvider implements DebridProvider {
  TorboxProvider({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://api.torbox.app/v1/api',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
              // Let us read the JSON error envelope on 4xx instead of throwing.
              validateStatus: (code) => code != null && code < 500,
            ));

  final Dio _dio;

  @override
  DebridProviderInfo get info => const DebridProviderInfo(
        id: 'torbox',
        name: 'TorBox',
        apiKeyHelp: 'Settings → API key on torbox.app',
      );

  @override
  bool isConfigured(String? apiKey) => apiKey != null && apiKey.trim().isNotEmpty;

  Options _auth(String apiKey) =>
      Options(headers: {'Authorization': 'Bearer ${apiKey.trim()}'});

  @override
  Future<String?> validateKey(String apiKey) async {
    try {
      final res = await _dio.get('/user/me', options: _auth(apiKey));
      if (res.statusCode == 200 && res.data is Map) return null;
      if (res.statusCode == 401 || res.statusCode == 403) {
        return 'Invalid TorBox API key';
      }
      return 'TorBox returned ${res.statusCode}';
    } catch (_) {
      return 'Could not reach TorBox';
    }
  }

  @override
  Future<DebridResult> resolveFile(
    DebridFileRequest req, {
    required String apiKey,
  }) async {
    try {
      // 1. Create-or-get. TorBox dedups by infohash, so re-posting an existing
      //    magnet is safe; we read the torrent_id when present.
      final created = await _dio.post(
        '/torrents/createtorrent',
        data: FormData.fromMap({'magnet': req.magnet, 'allow_zip': 'false'}),
        options: _auth(apiKey),
      );
      final authErr = _authError(created);
      if (authErr != null) return authErr;

      final createdData = _data(created);
      int? torrentId =
          createdData is Map ? _asInt(createdData['torrent_id']) : null;

      // 2. Poll current state via mylist (by id when we have it).
      final Map<String, dynamic>? torrent = torrentId != null
          ? await _torrentById(torrentId, apiKey)
          : await _torrentByHash(req.infohash, apiKey);

      if (torrent == null) {
        // Freshly queued and not yet listed — treat as caching.
        return const DebridCaching();
      }
      torrentId ??= _asInt(torrent['id']);

      final present = torrent['download_present'] == true;
      final finished = torrent['download_finished'] == true;
      final progress = _asDouble(torrent['progress']);

      if (!(present && finished) || torrentId == null) {
        return DebridCaching(progress: progress);
      }

      // 3. Ready — pick the file and request a direct link.
      final files = (torrent['files'] as List?) ?? const [];
      final fileId = _pickFileId(files, req);
      if (fileId == null) return const DebridNotCached();

      final dl = await _dio.get(
        '/torrents/requestdl',
        queryParameters: {
          'token': apiKey.trim(),
          'torrent_id': torrentId,
          'file_id': fileId,
        },
        options: _auth(apiKey),
      );
      final dlAuth = _authError(dl);
      if (dlAuth != null) return dlAuth;

      final url = _data(dl);
      if (url is String && url.isNotEmpty) {
        return DebridReady(url);
      }
      return const DebridError('TorBox did not return a download link');
    } on DioException catch (e) {
      return DebridError(e.message ?? 'TorBox request failed');
    } catch (e) {
      return DebridError('TorBox error: $e');
    }
  }

  Future<Map<String, dynamic>?> _torrentById(int id, String apiKey) async {
    final res = await _dio.get(
      '/torrents/mylist',
      queryParameters: {'id': id, 'bypass_cache': 'true'},
      options: _auth(apiKey),
    );
    final data = _data(res);
    if (data is Map<String, dynamic>) return data;
    if (data is List && data.isNotEmpty) {
      return data.first as Map<String, dynamic>;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _torrentByHash(
      String infohash, String apiKey) async {
    final res = await _dio.get(
      '/torrents/mylist',
      queryParameters: {'bypass_cache': 'true'},
      options: _auth(apiKey),
    );
    final data = _data(res);
    if (data is! List) return null;
    for (final item in data) {
      if (item is Map<String, dynamic> &&
          (item['hash'] as String?)?.toLowerCase() == infohash) {
        return item;
      }
    }
    return null;
  }

  /// Choose the TorBox file id for the requested file: prefer a filename match,
  /// then the positional file index, then the sole file. Rejects a candidate
  /// whose size grossly mismatches the expected size.
  Object? _pickFileId(List<dynamic> files, DebridFileRequest req) {
    if (files.isEmpty) return null;

    Map? byName;
    if (req.filePath != null && req.filePath!.isNotEmpty) {
      final target = p.basename(req.filePath!).toLowerCase();
      for (final f in files) {
        if (f is Map) {
          final name = (f['name'] as String?)?.toLowerCase() ?? '';
          if (name == target || name.endsWith('/$target')) {
            byName = f;
            break;
          }
        }
      }
    }

    final chosen = byName ??
        (req.fileIndex >= 0 && req.fileIndex < files.length
            ? files[req.fileIndex] as Map?
            : null) ??
        (files.length == 1 ? files.first as Map? : null);
    if (chosen == null) return null;

    if (req.expectedSize > 0) {
      final size = _asInt(chosen['size']) ?? 0;
      if (size > 0 && !_sizesClose(size, req.expectedSize)) return null;
    }
    return chosen['id'];
  }
}

// -- shared parsing helpers --------------------------------------------------

Object? _data(Response res) {
  final body = res.data;
  if (body is Map<String, dynamic>) return body['data'];
  return null;
}

DebridError? _authError(Response res) {
  if (res.statusCode == 401 || res.statusCode == 403) {
    return const DebridError('Invalid or expired API key', authError: true);
  }
  if (res.statusCode == 429) {
    return const DebridError('Rate limited', rateLimited: true);
  }
  return null;
}

int? _asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : null);

double? _asDouble(Object? v) => v is num ? v.toDouble() : null;

bool _sizesClose(int a, int b) {
  final larger = a > b ? a : b;
  return (a - b).abs() <= (larger * 0.05).ceil();
}

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import 'debrid_provider.dart';

/// Real-Debrid (https://real-debrid.com) debrid provider.
///
/// Flow: find-or-add the magnet, read `/torrents/info/{id}`, select the target
/// file if the torrent is waiting for selection, poll until `downloaded`, then
/// `/unrestrict/link` the matching link into a direct URL. Auth is the private
/// API token from real-debrid.com/apitoken.
class RealDebridProvider implements DebridProvider {
  RealDebridProvider({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://api.real-debrid.com/rest/1.0',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
              validateStatus: (code) => code != null && code < 500,
            ));

  final Dio _dio;

  @override
  DebridProviderInfo get info => const DebridProviderInfo(
        id: 'realdebrid',
        name: 'Real-Debrid',
        apiKeyHelp: 'Private API token at real-debrid.com/apitoken',
      );

  @override
  bool isConfigured(String? apiKey) => apiKey != null && apiKey.trim().isNotEmpty;

  Options _auth(String apiKey) =>
      Options(headers: {'Authorization': 'Bearer ${apiKey.trim()}'});

  @override
  Future<String?> validateKey(String apiKey) async {
    try {
      final res = await _dio.get('/user', options: _auth(apiKey));
      if (res.statusCode == 200 && res.data is Map) return null;
      if (res.statusCode == 401 || res.statusCode == 403) {
        return 'Invalid Real-Debrid token';
      }
      return 'Real-Debrid returned ${res.statusCode}';
    } catch (_) {
      return 'Could not reach Real-Debrid';
    }
  }

  @override
  Future<DebridResult> resolveFile(
    DebridFileRequest req, {
    required String apiKey,
  }) async {
    try {
      // 1. Find-or-add. addMagnet is NOT idempotent, so look for an existing
      //    torrent with this hash first.
      String? id;
      for (var page = 1; page <= 3 && id == null; page++) {
        final list = await _dio.get(
          '/torrents',
          queryParameters: {'limit': 100, 'page': page},
          options: _auth(apiKey),
        );
        final listErr = _authError(list);
        if (listErr != null) return listErr;

        final listData = list.data;
        if (listData is! List || listData.isEmpty) break;
        for (final item in listData) {
          if (item is Map &&
              (item['hash'] as String?)?.toLowerCase() == req.infohash) {
            id = item['id'] as String?;
            break;
          }
        }
        if (listData.length < 100) break;
      }

      if (id == null) {
        final added = await _dio.post(
          '/torrents/addMagnet',
          data: FormData.fromMap({'magnet': req.magnet}),
          options: _auth(apiKey),
        );
        final err = _authError(added);
        if (err != null) return err;
        final data = added.data;
        id = data is Map ? data['id'] as String? : null;
        if (id == null) return const DebridError('Real-Debrid did not return an id');
      }

      // 2. Read state.
      final info = await _dio.get('/torrents/info/$id', options: _auth(apiKey));
      final infoErr = _authError(info);
      if (infoErr != null) return infoErr;
      if (info.statusCode == 404) {
        // Torrent deleted server-side; the next poll re-adds the magnet.
        return const DebridCaching();
      }
      final data = info.data;
      if (data is! Map) return const DebridCaching();

      final status = data['status'] as String? ?? '';
      final files = (data['files'] as List?) ?? const [];
      final links = (data['links'] as List?) ?? const [];
      final progress = _asDouble(data['progress']);

      switch (status) {
        case 'magnet_conversion':
        case 'queued':
        case 'downloading':
        case 'compressing':
        case 'uploading':
          return DebridCaching(
              progress: progress == null ? null : progress / 100.0);

        case 'waiting_files_selection':
          final target = _pickFile(files, req);
          if (target == null) return const DebridNotCached();
          final sel = await _dio.post(
            '/torrents/selectFiles/$id',
            data: FormData.fromMap({'files': '${target['id']}'}),
            options: _auth(apiKey),
          );
          final selErr = _authError(sel);
          if (selErr != null) return selErr;
          final selCode = sel.statusCode ?? 0;
          if (selCode == 404) {
            // Torrent vanished; the next poll re-adds it.
            return const DebridCaching();
          }
          if (selCode >= 400) {
            return DebridError(
              'Real-Debrid selectFiles failed ($selCode)',
              permanent: true,
            );
          }
          return const DebridCaching();

        case 'downloaded':
          final target = _pickFile(files, req);
          if (target == null) return const DebridNotCached();
          final link = _linkForFile(files, links, target);
          if (link == null) {
            // Wrong file was selected earlier — delete so the next poll
            // re-adds it and selects the right one.
            await _dio.delete('/torrents/delete/$id', options: _auth(apiKey));
            return const DebridCaching();
          }
          final unres = await _dio.post(
            '/unrestrict/link',
            data: FormData.fromMap({'link': link}),
            options: _auth(apiKey),
          );
          final unresErr = _authError(unres);
          if (unresErr != null) return unresErr;
          final body = unres.data;
          final url = body is Map ? body['download'] as String? : null;
          if (url != null && url.isNotEmpty) {
            return DebridReady(url,
                filename: body is Map ? body['filename'] as String? : null,
                size: body is Map ? _asInt(body['filesize']) : null);
          }
          return const DebridError('Real-Debrid did not return a link');

        case 'magnet_error':
        case 'dead':
          return const DebridNotCached();
        default: // 'error', 'virus', unknown
          return DebridError('Real-Debrid status: $status');
      }
    } on DioException catch (e) {
      return DebridError(e.message ?? 'Real-Debrid request failed');
    } catch (e) {
      return DebridError('Real-Debrid error: $e');
    }
  }

  /// Choose the torrent file for the requested file: filename match, then
  /// positional index, then the sole file. Size-checked when known.
  Map? _pickFile(List<dynamic> files, DebridFileRequest req) {
    if (files.isEmpty) return null;

    Map? byName;
    if (req.filePath != null && req.filePath!.isNotEmpty) {
      final target = p.basename(req.filePath!).toLowerCase();
      for (final f in files) {
        if (f is Map) {
          final path = (f['path'] as String?)?.toLowerCase() ?? '';
          if (path == target || path.endsWith('/$target')) {
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
      final size = _asInt(chosen['bytes']) ?? 0;
      if (size > 0 && !_sizesClose(size, req.expectedSize)) return null;
    }
    return chosen;
  }

  /// Real-Debrid's `links` correspond, in order, to the SELECTED files (by file
  /// id ascending). Map the chosen file to its link by position among selected.
  String? _linkForFile(List<dynamic> files, List<dynamic> links, Map target) {
    if (links.isEmpty) return null;
    final selected = files
        .whereType<Map>()
        .where((f) => f['selected'] == 1)
        .toList()
      ..sort((a, b) => (_asInt(a['id']) ?? 0).compareTo(_asInt(b['id']) ?? 0));
    final idx = selected.indexWhere((f) => f['id'] == target['id']);
    if (idx >= 0 && idx < links.length) return links[idx] as String?;
    return null;
  }
}

// -- shared parsing helpers --------------------------------------------------

DebridError? _authError(Response res) {
  if (res.statusCode == 401 || res.statusCode == 403) {
    return const DebridError('Invalid or expired token', authError: true);
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

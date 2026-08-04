import 'package:dio/dio.dart';

import 'metadata_provider.dart';

class SteamGridDbProvider extends GameMetadataProvider {
  SteamGridDbProvider({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://www.steamgriddb.com/api/v2',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
              validateStatus: (code) => code != null && code < 500,
            ));

  final Dio _dio;

  static const _maxArtwork = 6;

  @override
  MetadataProviderInfo get info => const MetadataProviderInfo(
        id: 'steamgriddb',
        name: 'SteamGridDB',
      );

  @override
  List<CredentialField> get credentialFields => const [
        CredentialField(key: 'apiKey', label: 'API key', obscure: true),
      ];

  Options _auth(Map<String, String> creds) => Options(
        headers: {'Authorization': 'Bearer ${creds['apiKey']?.trim() ?? ''}'},
      );

  @override
  Future<String?> validateCredentials(Map<String, String> creds) async {
    try {
      final res = await _dio.get(
        '/search/autocomplete/mario',
        options: _auth(creds),
      );
      if (res.statusCode == 401 || res.statusCode == 403) {
        return 'Invalid SteamGridDB API key';
      }
      final body = res.data;
      if (res.statusCode == 200 && body is Map && body['success'] == true) {
        return null;
      }
      return 'SteamGridDB returned ${res.statusCode}';
    } catch (_) {
      return 'Could not reach SteamGridDB';
    }
  }

  @override
  Future<MetadataResult> fetch({
    required String title,
    required String platform,
    required Map<String, String> creds,
  }) async {
    try {
      final search = await _dio.get(
        '/search/autocomplete/${Uri.encodeComponent(title)}',
        options: _auth(creds),
      );
      final searchError = _envelopeError(search);
      if (searchError != null) return searchError;

      final results = ((search.data as Map)['data'] as List?)
              ?.whereType<Map>()
              .toList() ??
          const [];
      if (results.isEmpty) return const MetadataNoMatch();

      final target = title.toLowerCase();
      final game = results.firstWhere(
        (g) => (g['name'] as String?)?.toLowerCase() == target,
        orElse: () => results.first,
      );
      final id = game['id'];
      if (id is! int) return const MetadataNoMatch();

      final urls = <String>[
        ...await _mediaUrls('/heroes/game/$id', creds),
        ...await _mediaUrls('/grids/game/$id', creds),
      ];
      return MetadataFound(artworkUrls: urls.take(_maxArtwork).toList());
    } on DioException catch (e) {
      return MetadataError(e.message ?? 'SteamGridDB request failed');
    } catch (e) {
      return MetadataError('SteamGridDB error: $e');
    }
  }

  Future<List<String>> _mediaUrls(String path, Map<String, String> creds) async {
    try {
      final res = await _dio.get(path, options: _auth(creds));
      final body = res.data;
      if (body is! Map || body['success'] != true) return const [];
      return (body['data'] as List?)
              ?.whereType<Map>()
              .map((m) => m['url'] as String?)
              .whereType<String>()
              .toList() ??
          const [];
    } catch (_) {
      return const [];
    }
  }

  MetadataError? _envelopeError(Response res) {
    if (res.statusCode == 401 || res.statusCode == 403) {
      return const MetadataError('Invalid SteamGridDB API key', authError: true);
    }
    final body = res.data;
    if (body is! Map) {
      return const MetadataError('SteamGridDB: unexpected response');
    }
    if (body['success'] == false) {
      final errors =
          (body['errors'] as List?)?.whereType<String>().join(', ') ?? '';
      return MetadataError(
        'SteamGridDB: ${errors.isNotEmpty ? errors : 'request failed'}',
      );
    }
    return null;
  }
}

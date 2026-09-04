import 'dart:convert';

import 'package:dio/dio.dart';

import 'metadata_provider.dart';
import 'screenscraper_systems.dart';

// ScreenScraper returns errors as HTTP 200 plain text, not JSON.
class ScreenScraperProvider extends GameMetadataProvider {
  ScreenScraperProvider({Dio? dio, String? devId, String? devPassword})
      : _devId =
            devId ?? const String.fromEnvironment('SCREENSCRAPER_DEV_ID'),
        _devPassword = devPassword ??
            const String.fromEnvironment('SCREENSCRAPER_DEV_PASSWORD'),
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://api.screenscraper.fr/api2',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
              validateStatus: (code) => code != null && code < 500,
            ));

  final Dio _dio;
  final String _devId;
  final String _devPassword;

  @override
  MetadataProviderInfo get info => const MetadataProviderInfo(
        id: 'screenscraper',
        name: 'ScreenScraper',
      );

  @override
  List<CredentialField> get credentialFields => const [
        CredentialField(key: 'username', label: 'Username'),
        CredentialField(key: 'password', label: 'Password', obscure: true),
      ];

  Map<String, Object> _authParams(Map<String, String> creds) {
    return {
      if (_devId.isNotEmpty) 'devid': _devId,
      if (_devPassword.isNotEmpty) 'devpassword': _devPassword,
      'softname': 'romgi',
      'output': 'json',
      'ssid': creds['username']?.trim() ?? '',
      'sspassword': creds['password']?.trim() ?? '',
    };
  }

  @override
  Future<String?> validateCredentials(Map<String, String> creds) async {
    try {
      final res = await _dio.get(
        '/ssuserInfos.php',
        queryParameters: _authParams(creds),
      );
      if (res.statusCode == 401 || res.statusCode == 403) {
        return 'Invalid ScreenScraper credentials';
      }
      final body = _decoded(res);
      if (res.statusCode == 200 && body is Map) return null;
      if (res.data is String) return _textError(res.data as String).message;
      return 'ScreenScraper returned ${res.statusCode}';
    } catch (_) {
      return 'Could not reach ScreenScraper';
    }
  }

  @override
  Future<MetadataResult> fetch({
    required String title,
    required String platform,
    required Map<String, String> creds,
  }) async {
    final systemId = screenScraperSystemIds[platform];
    if (systemId == null) return const MetadataNoMatch();

    try {
      final res = await _dio.get(
        '/jeuRecherche.php',
        queryParameters: {
          ..._authParams(creds),
          'systemeid': systemId,
          'recherche': title,
        },
      );
      if (res.statusCode == 400 || res.statusCode == 404) {
        return const MetadataNoMatch();
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        return const MetadataError(
          'Invalid ScreenScraper credentials',
          authError: true,
        );
      }
      if (res.statusCode == 429) {
        return const MetadataError('ScreenScraper quota exceeded');
      }

      final body = _decoded(res);
      if (body is! Map) {
        if (res.data is String) return _textError(res.data as String);
        return const MetadataError('ScreenScraper: unexpected response');
      }

      final jeux = ((body['response'] as Map?)?['jeux'] as List?)
              ?.whereType<Map>()
              .toList() ??
          const [];
      if (jeux.isEmpty) return const MetadataNoMatch();

      final jeu = _bestMatch(jeux, title);
      return MetadataFound(
        description: _synopsis(jeu),
        screenshotUrls: _screenshots(jeu),
      );
    } on DioException catch (e) {
      return MetadataError(e.message ?? 'ScreenScraper request failed');
    } catch (e) {
      return MetadataError('ScreenScraper error: $e');
    }
  }

  Map _bestMatch(List<Map> jeux, String title) {
    final target = title.toLowerCase();
    for (final jeu in jeux) {
      final noms = (jeu['noms'] as List?)?.whereType<Map>() ?? const [];
      for (final nom in noms) {
        if ((nom['text'] as String?)?.toLowerCase() == target) return jeu;
      }
    }
    return jeux.first;
  }

  String? _synopsis(Map jeu) {
    final entries =
        (jeu['synopsis'] as List?)?.whereType<Map>().toList() ?? const [];
    if (entries.isEmpty) return null;
    final chosen = entries.firstWhere(
      (e) => e['langue'] == 'en',
      orElse: () => entries.first,
    );
    final text = (chosen['text'] as String?)?.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  List<String> _screenshots(Map jeu) {
    final medias = (jeu['medias'] as List?)?.whereType<Map>() ?? const [];
    final urls = <String>[];
    for (final media in medias) {
      final type = media['type'];
      if (type != 'ss' && type != 'sstitle') continue;
      final url = media['url'] as String?;
      if (url != null && url.isNotEmpty) urls.add(url);
      if (urls.length >= 8) break;
    }
    return urls;
  }
}

Object? _decoded(Response res) {
  final body = res.data;
  if (body is Map || body is List) return body;
  if (body is String) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }
  return null;
}

MetadataError _textError(String text) {
  final trimmed = text.trim();
  final lower = trimmed.toLowerCase();
  if (lower.contains('erreur de login')) {
    return const MetadataError(
      'Invalid ScreenScraper credentials',
      authError: true,
    );
  }
  if (lower.contains('votre quota')) {
    return const MetadataError('ScreenScraper quota exceeded');
  }
  final message = trimmed.length > 120 ? trimmed.substring(0, 120) : trimmed;
  return MetadataError('ScreenScraper: $message');
}

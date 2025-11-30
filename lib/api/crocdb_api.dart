import 'package:dio/dio.dart';
import '../models/models.dart';

class CrocDbApi {
  static const String baseUrl = 'https://api.crocdb.net';

  final Dio _dio;

  CrocDbApi({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
              headers: {
                'Content-Type': 'application/json',
              },
            ));

  /// Fetch all available platforms
  Future<List<Platform>> getPlatforms() async {
    final response = await _dio.get('/platforms');
    final Map<String, dynamic> responseData = response.data;
    final Map<String, dynamic> platforms = responseData['data']['platforms'];

    return platforms.entries.map((entry) {
      final platformData = entry.value as Map<String, dynamic>;
      return Platform(
        id: entry.key,
        brand: platformData['brand'] as String,
        name: platformData['name'] as String,
      );
    }).toList();
  }

  /// Fetch all available regions
  Future<List<Region>> getRegions() async {
    final response = await _dio.get('/regions');
    final Map<String, dynamic> responseData = response.data;
    final Map<String, dynamic> regions = responseData['data']['regions'];

    return regions.entries.map((entry) {
      return Region(
        id: entry.key,
        name: entry.value as String,
      );
    }).toList();
  }

  /// Search for ROM entries (POST method)
  Future<SearchResult> search({
    String? query,
    List<String>? platforms,
    List<String>? regions,
    int page = 1,
    int maxResults = 100,
  }) async {
    final Map<String, dynamic> body = {
      'page': page,
      'max_results': maxResults,
    };

    if (query != null && query.isNotEmpty) {
      body['search_key'] = query;
    }

    if (platforms != null && platforms.isNotEmpty) {
      body['platforms'] = platforms;
    }

    if (regions != null && regions.isNotEmpty) {
      body['regions'] = regions;
    }

    final response = await _dio.post('/search', data: body);
    final Map<String, dynamic> responseData = response.data;
    return SearchResult.fromJson(responseData['data'] as Map<String, dynamic>);
  }

  /// Get a specific entry by slug (POST method)
  Future<RomEntry> getEntry(String slug) async {
    final response = await _dio.post('/entry', data: {'slug': slug});
    final Map<String, dynamic> responseData = response.data;
    return RomEntry.fromJson(responseData['data']['entry'] as Map<String, dynamic>);
  }

  /// Get a random entry
  Future<RomEntry> getRandomEntry() async {
    final response = await _dio.get('/entry/random');
    final Map<String, dynamic> responseData = response.data;
    return RomEntry.fromJson(responseData['data']['entry'] as Map<String, dynamic>);
  }
}

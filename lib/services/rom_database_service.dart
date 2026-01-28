import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

/// Version metadata for the remote database
class DatabaseVersion {
  final String version;
  final DateTime generatedAt;
  final int size;
  final int uncompressedSize;
  final int entries;
  final int links;
  final int platforms;

  const DatabaseVersion({
    required this.version,
    required this.generatedAt,
    required this.size,
    required this.uncompressedSize,
    required this.entries,
    required this.links,
    required this.platforms,
  });

  factory DatabaseVersion.fromJson(Map<String, dynamic> json) {
    return DatabaseVersion(
      version: json['version'] as String,
      generatedAt: DateTime.parse(json['generated_at'] as String),
      size: json['size'] as int,
      uncompressedSize: json['uncompressed_size'] as int,
      entries: json['entries'] as int,
      links: json['links'] as int,
      platforms: json['platforms'] as int,
    );
  }
}

/// Service for managing the ROM catalog database
class RomDatabaseService {
  // Raw GitHub URL for database files in the repository
  static const String _baseUrl =
      'https://raw.githubusercontent.com/caprado/romgi/main/db';

  static const String _dbFileName = 'romdb.db';
  static const String _versionFileName = 'version.json';

  Database? _database;
  final Dio _dio;

  RomDatabaseService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(minutes: 10),
              ),
            );

  /// Get the path to the database file
  Future<String> get _dbPath async {
    final appDir = await getApplicationDocumentsDirectory();
    return p.join(appDir.path, _dbFileName);
  }

  /// Get the path to the local version file
  Future<String> get _localVersionPath async {
    final appDir = await getApplicationDocumentsDirectory();
    return p.join(appDir.path, _versionFileName);
  }

  /// Check if the database is ready to use
  /// This verifies the file exists AND the database is usable
  Future<bool> isDatabaseReady() async {
    final dbPath = await _dbPath;
    if (!File(dbPath).existsSync()) return false;

    // Verify the database is actually usable (catches FTS5/FTS4 issues)
    try {
      final db = await database;
      // Try a simple query that uses FTS to verify it works
      await db.rawQuery('SELECT COUNT(*) FROM entries LIMIT 1');
      return true;
    } catch (e) {
      // Database exists but is corrupted or incompatible - delete it
      await deleteDatabase();
      return false;
    }
  }

  /// Delete the local database (for re-download or reset)
  Future<void> deleteDatabase() async {
    await _closeDatabase();
    final dbPath = await _dbPath;
    final versionPath = await _localVersionPath;

    final dbFile = File(dbPath);
    if (dbFile.existsSync()) {
      await dbFile.delete();
    }

    final versionFile = File(versionPath);
    if (versionFile.existsSync()) {
      await versionFile.delete();
    }
  }

  /// Get the local database version, if available
  Future<DatabaseVersion?> getLocalVersion() async {
    try {
      final versionPath = await _localVersionPath;
      final file = File(versionPath);
      if (!file.existsSync()) return null;

      final content = await file.readAsString();
      return DatabaseVersion.fromJson(json.decode(content));
    } catch (e) {
      return null;
    }
  }

  /// Check for updates by comparing local and remote versions
  Future<DatabaseVersion?> checkForUpdate() async {
    try {
      final response = await _dio.get('$_baseUrl/$_versionFileName');
      final remoteVersion = DatabaseVersion.fromJson(response.data);
      final localVersion = await getLocalVersion();

      if (localVersion == null ||
          remoteVersion.version != localVersion.version) {
        return remoteVersion;
      }

      return null; // No update available
    } catch (e) {
      return null;
    }
  }

  /// Download and install the database
  Future<void> downloadDatabase({
    required void Function(double progress) onProgress,
    CancelToken? cancelToken,
  }) async {
    final dbPath = await _dbPath;
    final versionPath = await _localVersionPath;
    final tempGzPath = '$dbPath.gz';

    try {
      // Download the compressed database
      await _dio.download(
        '$_baseUrl/$_dbFileName.gz',
        tempGzPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress(received / total);
          }
        },
        cancelToken: cancelToken,
      );

      // Decompress the database
      final gzFile = File(tempGzPath);
      final gzBytes = await gzFile.readAsBytes();
      final decompressed = GZipDecoder().decodeBytes(gzBytes);

      // Write the decompressed database
      final dbFile = File(dbPath);
      await dbFile.writeAsBytes(decompressed);

      // Download and save the version file
      final versionResponse =
          await _dio.get('$_baseUrl/$_versionFileName');
      await File(versionPath).writeAsString(json.encode(versionResponse.data));

      // Clean up temp file
      await gzFile.delete();

      // Reset database connection
      await _closeDatabase();
    } catch (e) {
      // Clean up on failure
      final tempFile = File(tempGzPath);
      if (tempFile.existsSync()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }

  /// Get or open the database connection
  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }

    final dbPath = await _dbPath;
    _database = await openDatabase(dbPath, readOnly: true);
    return _database!;
  }

  Future<void> _closeDatabase() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }

  /// Get all platforms
  Future<List<Platform>> getPlatforms() async {
    final db = await database;
    final results = await db.query('platforms', orderBy: 'brand, name');

    return results.map((row) {
      return Platform(
        id: row['id'] as String,
        brand: row['brand'] as String,
        name: row['name'] as String,
      );
    }).toList();
  }

  /// Get all regions
  Future<List<Region>> getRegions() async {
    final db = await database;
    final results = await db.query('regions');

    return results.map((row) {
      return Region(
        id: row['id'] as String,
        name: row['name'] as String,
      );
    }).toList();
  }

  /// Search for ROM entries
  Future<SearchResult> search({
    String? query,
    List<String>? platforms,
    List<String>? regions,
    int page = 1,
    int maxResults = 100,
  }) async {
    final db = await database;
    final offset = (page - 1) * maxResults;
    final params = <dynamic>[];
    var whereClause = '';
    var joinClause = '';

    // Build the query based on filters
    if (query != null && query.isNotEmpty) {
      // Use FTS4 for text search
      final searchTerm = _escapeSearchTerm(query);

      // Count total matching entries (using FTS4 docid)
      var countSql = '''
        SELECT COUNT(DISTINCT e.slug) as count
        FROM entries e
        JOIN entries_fts fts ON fts.docid = e.rowid
      ''';

      var searchSql = '''
        SELECT DISTINCT e.slug, e.rom_id, e.title, e.platform, e.boxart_url,
               GROUP_CONCAT(DISTINCT r.name) as region_names
        FROM entries e
        JOIN entries_fts fts ON fts.docid = e.rowid
        LEFT JOIN regions_entries re ON re.entry = e.slug
        LEFT JOIN regions r ON r.id = re.region
      ''';

      whereClause = "WHERE entries_fts MATCH '$searchTerm'";

      if (platforms != null && platforms.isNotEmpty) {
        final placeholders = platforms.map((_) => '?').join(',');
        whereClause += ' AND e.platform IN ($placeholders)';
        params.addAll(platforms);
      }

      if (regions != null && regions.isNotEmpty) {
        final placeholders = regions.map((_) => '?').join(',');
        whereClause += ' AND re.region IN ($placeholders)';
        params.addAll(regions);
      }

      // Get total count
      final countParams = List<dynamic>.from(params);
      final countResult =
          await db.rawQuery('$countSql $whereClause', countParams);
      final totalResults = countResult.first['count'] as int;
      final totalPages = (totalResults / maxResults).ceil();

      // Get paginated results (FTS4 doesn't have bm25, order by title)
      searchSql += '''
        $whereClause
        GROUP BY e.slug
        ORDER BY e.title
        LIMIT ? OFFSET ?
      ''';
      params.addAll([maxResults, offset]);

      final results = await db.rawQuery(searchSql, params);
      final entries = await _mapResultsToEntries(db, results);

      return SearchResult(
        entries: entries,
        totalResults: totalResults,
        currentPage: page,
        totalPages: totalPages > 0 ? totalPages : 1,
        currentResults: entries.length,
      );
    } else {
      // No text search, just filter by platform/region
      var countSql = 'SELECT COUNT(DISTINCT e.slug) as count FROM entries e';
      var searchSql = '''
        SELECT DISTINCT e.slug, e.rom_id, e.title, e.platform, e.boxart_url,
               GROUP_CONCAT(DISTINCT r.name) as region_names
        FROM entries e
        LEFT JOIN regions_entries re ON re.entry = e.slug
        LEFT JOIN regions r ON r.id = re.region
      ''';

      final conditions = <String>[];

      if (platforms != null && platforms.isNotEmpty) {
        final placeholders = platforms.map((_) => '?').join(',');
        conditions.add('e.platform IN ($placeholders)');
        params.addAll(platforms);
      }

      if (regions != null && regions.isNotEmpty) {
        joinClause = 'JOIN regions_entries re ON re.entry = e.slug';
        final placeholders = regions.map((_) => '?').join(',');
        conditions.add('re.region IN ($placeholders)');
        params.addAll(regions);
      }

      if (conditions.isNotEmpty) {
        whereClause = 'WHERE ${conditions.join(' AND ')}';
      }

      // Get total count
      final countParams = List<dynamic>.from(params);
      final countResult =
          await db.rawQuery('$countSql $joinClause $whereClause', countParams);
      final totalResults = countResult.first['count'] as int;
      final totalPages = (totalResults / maxResults).ceil();

      // Get paginated results
      searchSql += '''
        $whereClause
        GROUP BY e.slug
        ORDER BY e.title
        LIMIT ? OFFSET ?
      ''';
      params.addAll([maxResults, offset]);

      final results = await db.rawQuery(searchSql, params);
      final entries = await _mapResultsToEntries(db, results);

      return SearchResult(
        entries: entries,
        totalResults: totalResults,
        currentPage: page,
        totalPages: totalPages > 0 ? totalPages : 1,
        currentResults: entries.length,
      );
    }
  }

  /// Get a specific entry by slug
  Future<RomEntry?> getEntry(String slug) async {
    final db = await database;

    // Get the entry
    final entryResults = await db.query(
      'entries',
      where: 'slug = ?',
      whereArgs: [slug],
    );

    if (entryResults.isEmpty) return null;

    final entry = entryResults.first;

    // Get regions
    final regionResults = await db.rawQuery('''
      SELECT r.name FROM regions r
      JOIN regions_entries re ON re.region = r.id
      WHERE re.entry = ?
    ''', [slug]);

    final regions = regionResults.map((r) => r['name'] as String).toList();

    // Get links
    final linkResults = await db.query(
      'links',
      where: 'entry = ?',
      whereArgs: [slug],
    );

    final links = linkResults.map((l) {
      return DownloadLink(
        name: l['name'] as String? ?? '',
        type: l['type'] as String? ?? 'Game',
        format: l['format'] as String? ?? '',
        url: l['url'] as String? ?? '',
        filename: l['filename'] as String? ?? '',
        host: l['host'] as String? ?? '',
        size: l['size'] as int? ?? 0,
        sizeStr: l['size_str'] as String? ?? '',
        sourceUrl: l['source_url'] as String? ?? '',
      );
    }).toList();

    return RomEntry(
      slug: entry['slug'] as String,
      romId: entry['rom_id'] as String?,
      title: entry['title'] as String,
      platform: entry['platform'] as String,
      boxartUrl: entry['boxart_url'] as String?,
      regions: regions,
      links: links,
    );
  }

  /// Get a random entry, optionally filtered by platform
  Future<RomEntry?> getRandomEntry({String? platformId}) async {
    final db = await database;

    String sql = 'SELECT slug FROM entries';
    final params = <dynamic>[];

    if (platformId != null) {
      sql += ' WHERE platform = ?';
      params.add(platformId);
    }

    sql += ' ORDER BY RANDOM() LIMIT 1';

    final results = await db.rawQuery(sql, params);

    if (results.isEmpty) return null;

    final slug = results.first['slug'] as String;
    return getEntry(slug);
  }

  /// Helper to escape search terms for FTS4
  String _escapeSearchTerm(String term) {
    // Escape special FTS characters and create a prefix search
    final escaped =
        term.replaceAll('"', '""').replaceAll("'", "''").toLowerCase();
    return '"$escaped"*';
  }

  /// Helper to map database results to RomEntry list
  Future<List<RomEntry>> _mapResultsToEntries(
    Database db,
    List<Map<String, Object?>> results,
  ) async {
    final entries = <RomEntry>[];

    for (final row in results) {
      final slug = row['slug'] as String;
      final regionNames = row['region_names'] as String?;

      entries.add(RomEntry(
        slug: slug,
        romId: row['rom_id'] as String?,
        title: row['title'] as String,
        platform: row['platform'] as String,
        boxartUrl: row['boxart_url'] as String?,
        regions: regionNames?.split(',') ?? [],
        links: [], // Links not needed for search results
      ));
    }

    return entries;
  }

  /// Close the database connection
  Future<void> close() async {
    await _closeDatabase();
  }
}

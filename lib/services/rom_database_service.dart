import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

/// Catalog schema this build expects. Mirror of
/// db/database/db_manager.py:SCHEMA_VERSION. On mismatch the local DB
/// is wiped and re-downloaded; no live migrations.
const int kAppExpectedSchemaVersion = 4;

class DatabaseVersion {
  final String version;
  final DateTime generatedAt;
  final int size;
  final int uncompressedSize;
  final int entries;
  final int links;
  final int platforms;

  /// Schema version of this DB build. Older builds omit this; absent → 1.
  final int schemaVersion;

  /// Minimum app version that can read this DB. Older builds omit this.
  final String? minAppVersion;

  final int? sources;

  const DatabaseVersion({
    required this.version,
    required this.generatedAt,
    required this.size,
    required this.uncompressedSize,
    required this.entries,
    required this.links,
    required this.platforms,
    this.schemaVersion = 1,
    this.minAppVersion,
    this.sources,
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
      schemaVersion: json['schema_version'] as int? ?? 1,
      minAppVersion: json['min_app_version'] as String?,
      sources: json['sources'] as int?,
    );
  }
}

/// Result of probing the remote DB against this app build.
class DatabaseUpdateCheck {
  /// New DB metadata when an update is available.
  final DatabaseVersion? available;

  /// True when the local DB schema is older than this app expects.
  /// Caller must delete + re-download before opening.
  final bool localIsStale;

  /// True when the remote DB requires a newer app build. Caller should
  /// prompt the user to update and not download.
  final bool appTooOld;

  const DatabaseUpdateCheck({
    this.available,
    this.localIsStale = false,
    this.appTooOld = false,
  });
}

/// Service for managing the ROM catalog database
class RomDatabaseService {
  // Raw GitHub URL for database files in the repository
  static const String _baseUrl =
      'https://raw.githubusercontent.com/caprado/romgi/main/db';

  static const String _dbFileName = 'romdb.db';
  static const String _versionFileName = 'version.json';

  Database? _database;
  bool _hasRaColumns = false;
  bool get hasRaColumns => _hasRaColumns;
  bool _hasEntryGroups = false;
  bool get hasEntryGroups => _hasEntryGroups;
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

  Future<bool> isDatabaseReady() async {
    final dbPath = await _dbPath;

    if (!File(dbPath).existsSync()) {
      return false;
    }

    // Verify the database is actually usable
    try {
      final db = await database;
      await db.rawQuery('''
        SELECT COUNT(*) FROM entries e
        JOIN entries_fts fts ON fts.docid = e.rowid
        LIMIT 1
      ''');
      return true;
    } catch (_) {
      // Database exists but is corrupted or incompatible - delete it
      await deleteDatabase();
      return false;
    }
  }

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

  Future<DatabaseVersion?> getLocalVersion() async {
    try {
      final versionPath = await _localVersionPath;
      final file = File(versionPath);
      if (!file.existsSync()) return null;

      final content = await file.readAsString();

      var decoded = json.decode(content);
      if (decoded is String) {
        decoded = json.decode(decoded);
      }

      return DatabaseVersion.fromJson(decoded as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<DatabaseVersion?> checkForUpdate() async {
    final result = await checkRemoteForUpdate(currentAppVersion: null);
    return result.available;
  }

  /// Probe the remote version manifest and decide whether the local DB is
  /// usable. Pass [currentAppVersion] (e.g. from `package_info_plus`) so
  /// the check can flag DBs that require a newer app build.
  Future<DatabaseUpdateCheck> checkRemoteForUpdate({
    required String? currentAppVersion,
  }) async {
    try {
      final response = await _dio.get('$_baseUrl/$_versionFileName');
      final remote = DatabaseVersion.fromJson(
        response.data is String
            ? json.decode(response.data as String) as Map<String, dynamic>
            : response.data as Map<String, dynamic>,
      );
      final local = await getLocalVersion();

      final appTooOld = currentAppVersion != null &&
          remote.minAppVersion != null &&
          _isVersionLessThan(currentAppVersion, remote.minAppVersion!);

      final localIsStale = local != null &&
          local.schemaVersion < kAppExpectedSchemaVersion;

      final hasUpdate = local == null || remote.version != local.version;

      return DatabaseUpdateCheck(
        available: hasUpdate ? remote : null,
        localIsStale: localIsStale,
        appTooOld: appTooOld,
      );
    } catch (_) {
      return const DatabaseUpdateCheck();
    }
  }

  /// Local DB is from an older schema than this app expects. Caller
  /// should `deleteDatabase()` and re-download before opening.
  Future<bool> isLocalDatabaseStale() async {
    final local = await getLocalVersion();
    if (local == null) return false;
    return local.schemaVersion < kAppExpectedSchemaVersion;
  }

  /// Numeric semver-ish compare ("1.2.0" < "1.10.0"). Falls back to
  /// string compare when either side has non-numeric components.
  static bool _isVersionLessThan(String a, String b) {
    List<int>? parts(String v) {
      final out = <int>[];
      for (final s in v.split('.')) {
        final n = int.tryParse(s);
        if (n == null) return null;
        out.add(n);
      }
      return out;
    }

    final pa = parts(a);
    final pb = parts(b);
    if (pa == null || pb == null) return a.compareTo(b) < 0;

    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final ai = i < pa.length ? pa[i] : 0;
      final bi = i < pb.length ? pb[i] : 0;
      if (ai != bi) return ai < bi;
    }
    return false;
  }

  Future<void> downloadDatabase({
    required void Function(double progress) onProgress,
    CancelToken? cancelToken,
  }) async {
    final dbPath = await _dbPath;
    final versionPath = await _localVersionPath;
    final tempGzPath = '$dbPath.gz';

    try {
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

      final gzFile = File(tempGzPath);
      final gzBytes = await gzFile.readAsBytes();
      final decompressed = gzip.decode(gzBytes);

      final dbFile = File(dbPath);
      await dbFile.writeAsBytes(decompressed);

      final versionResponse =
          await _dio.get('$_baseUrl/$_versionFileName');
      final versionData = versionResponse.data;
      final versionString = versionData is String ? versionData : json.encode(versionData);
      await File(versionPath).writeAsString(versionString);

      await gzFile.delete();

      await _closeDatabase();
    } catch (_) {
      // Clean up on failure
      final tempFile = File(tempGzPath);
      if (tempFile.existsSync()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }

    final dbPath = await _dbPath;
    _database = await openDatabase(dbPath, readOnly: true);
    final cols = await _database!.rawQuery('PRAGMA table_info(entries)');
    _hasRaColumns = cols.any((c) => c['name'] == 'ra_game_id');
    // Feature-detect the grouping tables so a pre-v4 catalog (or a mid-
    // transition DB) simply hides disc features instead of erroring.
    final groupTable = await _database!.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='entry_groups'",
    );
    _hasEntryGroups = groupTable.isNotEmpty;
    return _database!;
  }

  Future<void> _closeDatabase() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }

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

  String get _raSelectColumns =>
      _hasRaColumns ? ', e.ra_game_id, e.ra_num_achievements' : '';

  Future<SearchResult> search({
    String? query,
    List<String>? platforms,
    List<String>? regions,
    bool retroAchievementsOnly = false,
    int page = 1,
    int maxResults = 100,
  }) async {
    final db = await database;
    final offset = (page - 1) * maxResults;
    final params = <dynamic>[];
    var whereClause = '';

    if (query != null && query.isNotEmpty) {
      var searchSql = '''
        SELECT DISTINCT e.slug, e.rom_id, e.title, e.platform, e.boxart_url
               $_raSelectColumns,
               GROUP_CONCAT(DISTINCT r.name) as region_names
        FROM entries e
        LEFT JOIN regions_entries re ON re.entry = e.slug
        LEFT JOIN regions r ON r.id = re.region
      ''';

      final words = query.toLowerCase().split(RegExp(r'\s+'));
      final likeConditions = <String>[];
      for (final word in words) {
        final cleaned = word.replaceAll(RegExp(r'[^\w\d]'), '');
        if (cleaned.isEmpty) continue;
        likeConditions.add("LOWER(e.title) LIKE '%$cleaned%'");
      }

      final allConditions = [...likeConditions];

      if (platforms != null && platforms.isNotEmpty) {
        final placeholders = platforms.map((_) => '?').join(',');
        allConditions.add('e.platform IN ($placeholders)');
        params.addAll(platforms);
      }

      if (regions != null && regions.isNotEmpty) {
        final placeholders = regions.map((_) => '?').join(',');
        allConditions.add('re.region IN ($placeholders)');
        params.addAll(regions);
      }

      if (retroAchievementsOnly && _hasRaColumns) {
        allConditions.add('e.ra_game_id IS NOT NULL');
      }

      if (allConditions.isNotEmpty) {
        whereClause = 'WHERE ${allConditions.join(' AND ')}';
      }

      searchSql += '''
        $whereClause
        GROUP BY e.slug
        ORDER BY e.title
        LIMIT ? OFFSET ?
      ''';
      params.addAll([maxResults + 1, offset]);

      final results = await db.rawQuery(searchSql, params);
      final hasMore = results.length > maxResults;
      final limitedResults = hasMore ? results.sublist(0, maxResults) : results;
      final entries = await _mapResultsToEntries(db, limitedResults);

      final estimatedTotal = hasMore ? offset + maxResults + 1 : offset + entries.length;
      final estimatedPages = (estimatedTotal / maxResults).ceil();

      return SearchResult(
        entries: entries,
        totalResults: estimatedTotal,
        currentPage: page,
        totalPages: estimatedPages > 0 ? estimatedPages : 1,
        currentResults: entries.length,
      );
    } else {
      var searchSql = '''
        SELECT DISTINCT e.slug, e.rom_id, e.title, e.platform, e.boxart_url
               $_raSelectColumns,
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
        final placeholders = regions.map((_) => '?').join(',');
        conditions.add('re.region IN ($placeholders)');
        params.addAll(regions);
      }

      if (retroAchievementsOnly && _hasRaColumns) {
        conditions.add('e.ra_game_id IS NOT NULL');
      }

      if (conditions.isNotEmpty) {
        whereClause = 'WHERE ${conditions.join(' AND ')}';
      }

      searchSql += '''
        $whereClause
        GROUP BY e.slug
        ORDER BY e.title
        LIMIT ? OFFSET ?
      ''';
      params.addAll([maxResults + 1, offset]);

      final results = await db.rawQuery(searchSql, params);
      final hasMore = results.length > maxResults;
      final limitedResults = hasMore ? results.sublist(0, maxResults) : results;
      final entries = await _mapResultsToEntries(db, limitedResults);

      final estimatedTotal = hasMore ? offset + maxResults + 1 : offset + entries.length;
      final estimatedPages = (estimatedTotal / maxResults).ceil();

      return SearchResult(
        entries: entries,
        totalResults: estimatedTotal,
        currentPage: page,
        totalPages: estimatedPages > 0 ? estimatedPages : 1,
        currentResults: entries.length,
      );
    }
  }

  Future<RomEntry?> getEntry(String slug) async {
    final db = await database;

    final entryResults = await db.query(
      'entries',
      where: 'slug = ?',
      whereArgs: [slug],
    );

    if (entryResults.isEmpty) return null;

    final entry = entryResults.first;

    final regionResults = await db.rawQuery('''
      SELECT r.name FROM regions r
      JOIN regions_entries re ON re.region = r.id
      WHERE re.entry = ?
    ''', [slug]);

    final regions = regionResults.map((r) => r['name'] as String).toList();

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
        sourceId: l['source_id'] as String?,
        requiresAuth: (l['requires_auth'] as int? ?? 0) != 0,
        torrentInfohash: l['torrent_infohash'] as String?,
        torrentFileIndex: l['torrent_file_index'] as int?,
        torrentFilePath: l['torrent_file_path'] as String?,
      );
    }).toList();

    return RomEntry(
      slug: entry['slug'] as String,
      romId: entry['rom_id'] as String?,
      title: entry['title'] as String,
      platform: entry['platform'] as String,
      boxartUrl: entry['boxart_url'] as String?,
      raGameId: _hasRaColumns ? entry['ra_game_id'] as int? : null,
      raNumAchievements: _hasRaColumns ? entry['ra_num_achievements'] as int? : null,
      regions: regions,
      links: links,
    );
  }

  /// The group [slug] belongs to (e.g. its multi-disc set), or null if the
  /// entry is standalone or the catalog predates grouping. Members are
  /// ordered by disc index.
  Future<EntryGroup?> getEntryGroup(String slug) async {
    final db = await database;
    if (!_hasEntryGroups) return null;

    final membership = await db.query(
      'entry_group_members',
      columns: ['group_id'],
      where: 'entry = ?',
      whereArgs: [slug],
      limit: 1,
    );
    if (membership.isEmpty) return null;
    final groupId = membership.first['group_id'] as String;

    final groupRows = await db.query(
      'entry_groups',
      where: 'id = ?',
      whereArgs: [groupId],
      limit: 1,
    );
    if (groupRows.isEmpty) return null;
    final group = groupRows.first;

    final memberRows = await db.rawQuery('''
      SELECT gm.entry, gm.member_index, gm.member_label, e.title
      FROM entry_group_members gm
      JOIN entries e ON e.slug = gm.entry
      WHERE gm.group_id = ?
      ORDER BY gm.member_index
    ''', [groupId]);

    final members = memberRows.map((m) {
      return EntryGroupMember(
        slug: m['entry'] as String,
        title: m['title'] as String? ?? '',
        index: (m['member_index'] as int?) ?? 0,
        label: m['member_label'] as String? ?? '',
      );
    }).toList();

    return EntryGroup(
      id: group['id'] as String,
      kind: group['kind'] as String? ?? 'disc',
      title: group['title'] as String? ?? '',
      platform: group['platform'] as String? ?? '',
      members: members,
    );
  }

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
        raGameId: _hasRaColumns ? row['ra_game_id'] as int? : null,
        raNumAchievements: _hasRaColumns ? row['ra_num_achievements'] as int? : null,
        regions: regionNames?.split(',') ?? [],
        links: [], // Links not needed for search results
      ));
    }

    return entries;
  }

  Future<void> close() async {
    await _closeDatabase();
  }
}

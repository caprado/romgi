import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

class DatabaseService {
  static Database? _database;
  static const String _dbName = 'romgi.db';
  static const int _dbVersion = 3;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE downloads ADD COLUMN hidden_from_history INTEGER NOT NULL DEFAULT 0',
      );
    }

    if (oldVersion < 3) {
      // Add recently_viewed table
      await db.execute('''
        CREATE TABLE recently_viewed (
          slug TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          platform TEXT NOT NULL,
          boxart_url TEXT,
          viewed_at INTEGER NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX idx_recently_viewed_at ON recently_viewed(viewed_at DESC)',
      );

      // Add favorites table
      await db.execute('''
        CREATE TABLE favorites (
          slug TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          platform TEXT NOT NULL,
          boxart_url TEXT,
          added_at INTEGER NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX idx_favorites_added_at ON favorites(added_at DESC)',
      );
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // Downloads table for tracking download queue and history
    await db.execute('''
      CREATE TABLE downloads (
        id TEXT PRIMARY KEY,
        slug TEXT NOT NULL,
        title TEXT NOT NULL,
        platform TEXT NOT NULL,
        boxart_url TEXT,
        link_name TEXT NOT NULL,
        link_type TEXT NOT NULL,
        link_format TEXT NOT NULL,
        link_url TEXT NOT NULL,
        link_filename TEXT NOT NULL,
        link_host TEXT NOT NULL,
        link_size INTEGER NOT NULL,
        link_size_str TEXT NOT NULL,
        link_source_url TEXT NOT NULL,
        status INTEGER NOT NULL DEFAULT 0,
        progress REAL NOT NULL DEFAULT 0.0,
        downloaded_bytes INTEGER NOT NULL DEFAULT 0,
        total_bytes INTEGER NOT NULL DEFAULT 0,
        file_path TEXT,
        error TEXT,
        created_at INTEGER NOT NULL,
        completed_at INTEGER,
        hidden_from_history INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Index for faster queries
    await db.execute('CREATE INDEX idx_downloads_status ON downloads(status)');
    await db.execute('CREATE INDEX idx_downloads_slug ON downloads(slug)');
    await db.execute(
      'CREATE INDEX idx_downloads_platform ON downloads(platform)',
    );

    // Recently viewed table
    await db.execute('''
      CREATE TABLE recently_viewed (
        slug TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        platform TEXT NOT NULL,
        boxart_url TEXT,
        viewed_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_recently_viewed_at ON recently_viewed(viewed_at DESC)',
    );

    // Favorites/Wishlist table
    await db.execute('''
      CREATE TABLE favorites (
        slug TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        platform TEXT NOT NULL,
        boxart_url TEXT,
        added_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_favorites_added_at ON favorites(added_at DESC)',
    );
  }

  Future<void> insertDownload(DownloadTask task) async {
    final db = await database;
    await db.insert(
      'downloads',
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateDownload(DownloadTask task) async {
    final db = await database;
    await db.update(
      'downloads',
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  Future<void> deleteDownload(String id) async {
    final db = await database;

    await db.delete('downloads', where: 'id = ?', whereArgs: [id]);
  }

  Future<DownloadTask?> getDownload(String id) async {
    final db = await database;
    final maps = await db.query('downloads', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;

    return DownloadTask.fromMap(maps.first);
  }

  Future<List<DownloadTask>> getAllDownloads() async {
    final db = await database;
    final maps = await db.query('downloads', orderBy: 'created_at DESC');

    return maps.map((map) => DownloadTask.fromMap(map)).toList();
  }

  Future<List<DownloadTask>> getDownloadsByStatus(DownloadStatus status) async {
    final db = await database;
    final maps = await db.query(
      'downloads',
      where: 'status = ?',
      whereArgs: [status.index],
      orderBy: 'created_at ASC',
    );

    return maps.map((map) => DownloadTask.fromMap(map)).toList();
  }

  Future<List<DownloadTask>> getActiveDownloads() async {
    final db = await database;
    final maps = await db.query(
      'downloads',
      where: 'status IN (?, ?, ?, ?)',
      whereArgs: [
        DownloadStatus.pending.index,
        DownloadStatus.downloading.index,
        DownloadStatus.extracting.index,
        DownloadStatus.paused.index,
      ],
      orderBy: 'created_at ASC',
    );

    return maps.map((map) => DownloadTask.fromMap(map)).toList();
  }

  Future<List<DownloadTask>> getCompletedDownloads() async {
    final db = await database;
    final maps = await db.query(
      'downloads',
      where: 'status = ?',
      whereArgs: [DownloadStatus.completed.index],
      orderBy: 'completed_at DESC',
    );

    return maps.map((map) => DownloadTask.fromMap(map)).toList();
  }

  Future<List<DownloadTask>> getVisibleCompletedDownloads() async {
    final db = await database;
    final maps = await db.query(
      'downloads',
      where: 'status = ? AND hidden_from_history = 0',
      whereArgs: [DownloadStatus.completed.index],
      orderBy: 'completed_at DESC',
    );

    return maps.map((map) => DownloadTask.fromMap(map)).toList();
  }

  Future<void> hideFromHistory(String id) async {
    final db = await database;
    await db.update(
      'downloads',
      {'hidden_from_history': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> hideAllCompletedFromHistory() async {
    final db = await database;
    await db.update(
      'downloads',
      {'hidden_from_history': 1},
      where: 'status = ?',
      whereArgs: [DownloadStatus.completed.index],
    );
  }

  Future<bool> isSlugDownloaded(String slug) async {
    final db = await database;
    final result = await db.query(
      'downloads',
      where: 'slug = ? AND status = ?',
      whereArgs: [slug, DownloadStatus.completed.index],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  Future<List<DownloadTask>> getDownloadsByPlatform(String platform) async {
    final db = await database;
    final maps = await db.query(
      'downloads',
      where: 'platform = ? AND status = ?',
      whereArgs: [platform, DownloadStatus.completed.index],
      orderBy: 'title ASC',
    );

    return maps.map((map) => DownloadTask.fromMap(map)).toList();
  }

  Future<void> clearCompletedDownloads() async {
    final db = await database;
    await db.delete(
      'downloads',
      where: 'status = ?',
      whereArgs: [DownloadStatus.completed.index],
    );
  }

  Future<void> clearFailedDownloads() async {
    final db = await database;
    await db.delete(
      'downloads',
      where: 'status = ?',
      whereArgs: [DownloadStatus.failed.index],
    );
  }

  Future<DownloadTask?> findExistingDownload(String url) async {
    final db = await database;
    final maps = await db.query(
      'downloads',
      where: 'link_url = ? AND status != ?',
      whereArgs: [url, DownloadStatus.failed.index],
      limit: 1,
    );

    if (maps.isEmpty) return null;

    return DownloadTask.fromMap(maps.first);
  }

  Future<void> addRecentlyViewed({
    required String slug,
    required String title,
    required String platform,
    String? boxartUrl,
  }) async {
    final db = await database;
    await db.insert('recently_viewed', {
      'slug': slug,
      'title': title,
      'platform': platform,
      'boxart_url': boxartUrl,
      'viewed_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // Keep only last 50 entries
    await db.execute('''
      DELETE FROM recently_viewed WHERE slug NOT IN (
        SELECT slug FROM recently_viewed ORDER BY viewed_at DESC LIMIT 50
      )
    ''');
  }

  Future<List<RecentlyViewed>> getRecentlyViewed({int limit = 20}) async {
    final db = await database;
    final maps = await db.query(
      'recently_viewed',
      orderBy: 'viewed_at DESC',
      limit: limit,
    );

    return maps.map((map) => RecentlyViewed.fromMap(map)).toList();
  }

  Future<void> clearRecentlyViewed() async {
    final db = await database;
    await db.delete('recently_viewed');
  }

  Future<void> addFavorite({
    required String slug,
    required String title,
    required String platform,
    String? boxartUrl,
  }) async {
    final db = await database;
    await db.insert('favorites', {
      'slug': slug,
      'title': title,
      'platform': platform,
      'boxart_url': boxartUrl,
      'added_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> removeFavorite(String slug) async {
    final db = await database;
    await db.delete('favorites', where: 'slug = ?', whereArgs: [slug]);
  }

  Future<bool> isFavorite(String slug) async {
    final db = await database;
    final result = await db.query(
      'favorites',
      where: 'slug = ?',
      whereArgs: [slug],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  Future<List<Favorite>> getFavorites() async {
    final db = await database;
    final maps = await db.query('favorites', orderBy: 'added_at DESC');

    return maps.map((map) => Favorite.fromMap(map)).toList();
  }

  Future<int> getFavoriteCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM favorites');

    return Sqflite.firstIntValue(result) ?? 0;
  }
}

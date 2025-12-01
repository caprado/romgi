import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/database_service.dart';
import 'download_provider.dart';

/// Provider for recently viewed entries
final recentlyViewedProvider =
    StateNotifierProvider<RecentlyViewedNotifier, AsyncValue<List<RecentlyViewed>>>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return RecentlyViewedNotifier(db);
});

class RecentlyViewedNotifier extends StateNotifier<AsyncValue<List<RecentlyViewed>>> {
  final DatabaseService _db;

  RecentlyViewedNotifier(this._db) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final items = await _db.getRecentlyViewed(limit: 20);
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addEntry({
    required String slug,
    required String title,
    required String platform,
    String? boxartUrl,
  }) async {
    await _db.addRecentlyViewed(
      slug: slug,
      title: title,
      platform: platform,
      boxartUrl: boxartUrl,
    );
    await load();
  }

  Future<void> clear() async {
    await _db.clearRecentlyViewed();
    state = const AsyncValue.data([]);
  }
}

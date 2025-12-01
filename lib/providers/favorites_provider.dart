import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/database_service.dart';
import 'download_provider.dart';

/// Provider for all favorites
final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, AsyncValue<List<Favorite>>>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return FavoritesNotifier(db);
});

class FavoritesNotifier extends StateNotifier<AsyncValue<List<Favorite>>> {
  final DatabaseService _db;

  FavoritesNotifier(this._db) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final items = await _db.getFavorites();
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addFavorite({
    required String slug,
    required String title,
    required String platform,
    String? boxartUrl,
  }) async {
    await _db.addFavorite(
      slug: slug,
      title: title,
      platform: platform,
      boxartUrl: boxartUrl,
    );
    await load();
  }

  Future<void> removeFavorite(String slug) async {
    await _db.removeFavorite(slug);
    await load();
  }

  Future<void> toggleFavorite({
    required String slug,
    required String title,
    required String platform,
    String? boxartUrl,
  }) async {
    final isFav = await _db.isFavorite(slug);
    if (isFav) {
      await removeFavorite(slug);
    } else {
      await addFavorite(
        slug: slug,
        title: title,
        platform: platform,
        boxartUrl: boxartUrl,
      );
    }
  }
}

/// Provider to check if a specific slug is favorited
final isFavoriteProvider = FutureProvider.family<bool, String>((ref, slug) async {
  final db = ref.watch(databaseServiceProvider);
  return db.isFavorite(slug);
});

/// Provider for favorite count
final favoriteCountProvider = FutureProvider<int>((ref) async {
  final db = ref.watch(databaseServiceProvider);
  return db.getFavoriteCount();
});

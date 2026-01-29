import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/services.dart';
import 'download_provider.dart';

class LibraryState {
  final List<DownloadTask> items;
  final String? selectedPlatform;
  final String searchQuery;
  final bool isLoading;
  final Set<String> verifiedFiles; // Files that exist on disk

  const LibraryState({
    this.items = const [],
    this.selectedPlatform,
    this.searchQuery = '',
    this.isLoading = false,
    this.verifiedFiles = const {},
  });

  LibraryState copyWith({
    List<DownloadTask>? items,
    String? selectedPlatform,
    bool clearPlatform = false,
    String? searchQuery,
    bool? isLoading,
    Set<String>? verifiedFiles,
  }) {
    return LibraryState(
      items: items ?? this.items,
      selectedPlatform: clearPlatform
          ? null
          : (selectedPlatform ?? this.selectedPlatform),
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
      verifiedFiles: verifiedFiles ?? this.verifiedFiles,
    );
  }

  List<DownloadTask> get filteredItems {
    var result = items;

    if (selectedPlatform != null) {
      result = result
          .where((item) => item.platform == selectedPlatform)
          .toList();
    }

    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      result = result
          .where(
            (item) =>
                item.title.toLowerCase().contains(query) ||
                item.platform.toLowerCase().contains(query),
          )
          .toList();
    }

    return result;
  }

  List<String> get platforms {
    final platformSet = items.map((item) => item.platform).toSet();
    return platformSet.toList()..sort();
  }

  bool fileExists(String? path) {
    if (path == null) return false;

    return verifiedFiles.contains(path);
  }
}

class LibraryNotifier extends StateNotifier<LibraryState> {
  final DatabaseService _db;
  final StorageService _storage;

  LibraryNotifier(this._db, this._storage) : super(const LibraryState()) {
    refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);

    final completed = await _db.getCompletedDownloads();

    // Verify which files still exist
    final verified = <String>{};
    for (final item in completed) {
      final path = item.filePath;
      if (path != null) {
        try {
          if (await File(path).exists()) {
            verified.add(path);
          }
        } catch (e) {
          // Ignore errors checking file existence
        }
      }
    }

    state = state.copyWith(
      items: completed,
      verifiedFiles: verified,
      isLoading: false,
    );
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setSelectedPlatform(String? platform) {
    if (platform == null) {
      state = state.copyWith(clearPlatform: true);
    } else {
      state = state.copyWith(selectedPlatform: platform);
    }
  }

  Future<void> deleteItem(DownloadTask task, {bool deleteFile = true}) async {
    await _db.deleteDownload(task.id);

    // Delete file if requested
    if (deleteFile && task.filePath != null) {
      await _storage.deleteFile(task.filePath!);
    }

    await refresh();
  }

  Future<void> verifyFiles() async {
    state = state.copyWith(isLoading: true);

    final verified = <String>{};
    final itemsToRemove = <String>[];

    for (final item in state.items) {
      if (item.filePath != null) {
        if (await File(item.filePath!).exists()) {
          verified.add(item.filePath!);
        } else {
          // File is missing - mark for potential cleanup
          itemsToRemove.add(item.id);
        }
      }
    }

    state = state.copyWith(verifiedFiles: verified, isLoading: false);
  }

  /// Remove entries for missing files
  Future<void> cleanupMissingFiles() async {
    for (final item in state.items) {
      if (item.filePath != null &&
          !state.verifiedFiles.contains(item.filePath)) {
        await _db.deleteDownload(item.id);
      }
    }
    await refresh();
  }
}

final libraryProvider = StateNotifierProvider<LibraryNotifier, LibraryState>((
  ref,
) {
  final db = ref.watch(databaseServiceProvider);
  final storage = ref.watch(storageServiceProvider);

  return LibraryNotifier(db, storage);
});

/// Provider for all downloaded slugs (for badge display)
/// Watches libraryProvider to auto-refresh when library changes
final downloadedSlugsProvider = FutureProvider<Set<String>>((ref) async {
  final libraryState = ref.watch(libraryProvider);
  // Use library items if available (faster), otherwise fetch from db
  if (!libraryState.isLoading && libraryState.items.isNotEmpty) {
    return libraryState.items.map((task) => task.slug).toSet();
  }
  final db = ref.watch(databaseServiceProvider);
  final completed = await db.getCompletedDownloads();

  return completed.map((task) => task.slug).toSet();
});

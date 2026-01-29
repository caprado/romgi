import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/services.dart';
import 'internet_archive_auth_provider.dart';
import 'library_provider.dart';
import 'settings_provider.dart';

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return DatabaseService();
});

final storageServiceProvider = Provider<StorageService>((ref) {
  final storage = StorageService();

  // Watch settings and sync custom paths to storage service
  final settings = ref.watch(settingsProvider);
  if (!settings.isLoading) {
    storage.setCustomDownloadPath(settings.defaultDownloadPath);
    storage.setPlatformPaths(settings.platformPaths);
  }

  return storage;
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

final downloadServiceProvider = Provider<DownloadService>((ref) {
  final db = ref.watch(databaseServiceProvider);
  final storage = ref.watch(storageServiceProvider);
  final notifications = ref.watch(notificationServiceProvider);
  final iaAuth = ref.watch(internetArchiveAuthProvider);
  return DownloadService(
    db: db,
    storage: storage,
    notifications: notifications,
    iaAuth: iaAuth,
  );
});

class DownloadState {
  final List<DownloadTask> activeDownloads;
  final List<DownloadTask> completedDownloads;
  final List<DownloadTask> failedDownloads;
  final bool isLoading;
  final bool isInitialized;

  const DownloadState({
    this.activeDownloads = const [],
    this.completedDownloads = const [],
    this.failedDownloads = const [],
    this.isLoading = false,
    this.isInitialized = false,
  });

  DownloadState copyWith({
    List<DownloadTask>? activeDownloads,
    List<DownloadTask>? completedDownloads,
    List<DownloadTask>? failedDownloads,
    bool? isLoading,
    bool? isInitialized,
  }) {
    return DownloadState(
      activeDownloads: activeDownloads ?? this.activeDownloads,
      completedDownloads: completedDownloads ?? this.completedDownloads,
      failedDownloads: failedDownloads ?? this.failedDownloads,
      isLoading: isLoading ?? this.isLoading,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }

  DownloadTask? get currentDownload {
    final downloading = activeDownloads.where(
      (download) =>
          download.status == DownloadStatus.downloading ||
          download.status == DownloadStatus.extracting,
    );
    return downloading.isNotEmpty ? downloading.first : null;
  }

  List<DownloadTask> get currentDownloads {
    return activeDownloads
        .where(
          (download) =>
              download.status == DownloadStatus.downloading ||
              download.status == DownloadStatus.extracting,
        )
        .toList();
  }

  List<DownloadTask> get queuedDownloads {
    final queued = activeDownloads
        .where(
          (download) =>
              download.status == DownloadStatus.pending ||
              download.status == DownloadStatus.paused,
        )
        .toList();

    // Sort: pending first, then paused (paused items won't run until resumed)
    queued.sort((downloadA, downloadB) {
      if (downloadA.status == downloadB.status) return 0;
      if (downloadA.status == DownloadStatus.pending) return -1;

      return 1;
    });

    return queued;
  }
}

class DownloadNotifier extends StateNotifier<DownloadState> {
  final DownloadService _service;
  final void Function()? _onDownloadCompleted;
  StreamSubscription<DownloadTask>? _subscription;

  DownloadNotifier(
    this._service, {
    int maxConcurrentDownloads = 3,
    void Function()? onDownloadCompleted,
  }) : _onDownloadCompleted = onDownloadCompleted,
       super(const DownloadState()) {
    _service.setMaxConcurrentDownloads(maxConcurrentDownloads);
    _init();
  }

  void updateMaxConcurrentDownloads(int value) {
    _service.setMaxConcurrentDownloads(value);
  }

  Future<void> _init() async {
    state = state.copyWith(isLoading: true);

    await _service.initialize();
    await refresh();

    // Listen to download updates
    _subscription = _service.downloadStream.listen(_onDownloadUpdate);

    state = state.copyWith(isLoading: false, isInitialized: true);
  }

  void _onDownloadUpdate(DownloadTask task) {
    final activeList = List<DownloadTask>.from(state.activeDownloads);
    final completedList = List<DownloadTask>.from(state.completedDownloads);
    final failedList = List<DownloadTask>.from(state.failedDownloads);

    final existingIndex = activeList.indexWhere(
      (listItem) => listItem.id == task.id,
    );

    activeList.removeWhere((listItem) => listItem.id == task.id);
    completedList.removeWhere((listItem) => listItem.id == task.id);
    failedList.removeWhere((listItem) => listItem.id == task.id);

    if (task.status == DownloadStatus.completed) {
      completedList.insert(0, task);
      _onDownloadCompleted?.call();
    } else if (task.status == DownloadStatus.failed) {
      failedList.insert(0, task);
    } else {
      // Preserve position if task was already in active list, otherwise add to end
      if (existingIndex >= 0 && existingIndex < activeList.length) {
        activeList.insert(existingIndex, task);
      } else if (existingIndex >= 0) {
        activeList.add(task);
      } else {
        activeList.add(task);
      }
    }

    state = state.copyWith(
      activeDownloads: activeList,
      completedDownloads: completedList,
      failedDownloads: failedList,
    );
  }

  Future<void> refresh() async {
    final active = await _service.getActiveDownloads();
    final completed = await _service.getVisibleCompletedDownloads();
    final failed = await _service.getFailedDownloads();
    state = state.copyWith(
      activeDownloads: active,
      completedDownloads: completed,
      failedDownloads: failed,
    );
  }

  Future<(AddDownloadResult, DownloadTask)> addDownload({
    required String slug,
    required String title,
    required String platform,
    String? boxartUrl,
    required DownloadLink link,
  }) async {
    return _service.addDownload(
      slug: slug,
      title: title,
      platform: platform,
      boxartUrl: boxartUrl,
      link: link,
    );
  }

  Future<void> pauseDownload(String id) async {
    await _service.pauseDownload(id);
    await refresh();
  }

  Future<void> resumeDownload(String id) async {
    await _service.resumeDownload(id);
    await refresh();
  }

  Future<void> cancelDownload(String id) async {
    await _service.cancelDownload(id);
    await refresh();
  }

  Future<void> retryDownload(String id) async {
    await _service.retryDownload(id);
    await refresh();
  }

  Future<void> removeCompletedDownload(String id) async {
    await _service.hideCompletedDownload(id);
    await refresh();
  }

  Future<void> clearCompletedDownloads() async {
    await _service.clearCompletedDownloads();
    await refresh();
  }

  Future<bool> isDownloaded(String slug) async {
    return _service.isDownloaded(slug);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _service.dispose();
    super.dispose();
  }
}

final downloadProvider = StateNotifierProvider<DownloadNotifier, DownloadState>((
  ref,
) {
  final service = ref.watch(downloadServiceProvider);
  // Use read instead of watch to avoid recreating the notifier when settings change
  final settings = ref.read(settingsProvider);
  final notifier = DownloadNotifier(
    service,
    maxConcurrentDownloads: settings.maxConcurrentDownloads,
    onDownloadCompleted: () {
      ref.read(libraryProvider.notifier).refresh();
    },
  );

  // Listen for settings changes and update the service directly
  ref.listen<SettingsState>(settingsProvider, (previous, next) {
    if (previous?.maxConcurrentDownloads != next.maxConcurrentDownloads) {
      notifier.updateMaxConcurrentDownloads(next.maxConcurrentDownloads);
    }
  });

  return notifier;
});

// Helper provider to check if a slug is downloaded
final isDownloadedProvider = Provider.family<AsyncValue<bool>, String>((
  ref,
  slug,
) {
  final slugsAsync = ref.watch(downloadedSlugsProvider);

  return slugsAsync.whenData((slugs) => slugs.contains(slug));
});

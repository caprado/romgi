import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/rom_database_service.dart';

/// State for database setup process
enum DatabaseSetupStatus {
  checking,
  ready,
  needsDownload,
  downloading,
  error,
}

class DatabaseSetupState {
  final DatabaseSetupStatus status;
  final double progress;
  final String? errorMessage;
  final DatabaseVersion? availableVersion;

  const DatabaseSetupState({
    this.status = DatabaseSetupStatus.checking,
    this.progress = 0.0,
    this.errorMessage,
    this.availableVersion,
  });

  DatabaseSetupState copyWith({
    DatabaseSetupStatus? status,
    double? progress,
    String? errorMessage,
    DatabaseVersion? availableVersion,
  }) {
    return DatabaseSetupState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage,
      availableVersion: availableVersion ?? this.availableVersion,
    );
  }
}

/// Provider for database setup state
final databaseSetupProvider =
    StateNotifierProvider<DatabaseSetupNotifier, DatabaseSetupState>((ref) {
  return DatabaseSetupNotifier(ref);
});

class DatabaseSetupNotifier extends StateNotifier<DatabaseSetupState> {
  final RomDatabaseService _dbService = RomDatabaseService();
  CancelToken? _cancelToken;

  DatabaseSetupNotifier(Ref ref) : super(const DatabaseSetupState());

  Future<void> checkDatabase() async {
    state = const DatabaseSetupState(status: DatabaseSetupStatus.checking);

    try {
      final isReady = await _dbService.isDatabaseReady();

      if (isReady) {
        state = state.copyWith(status: DatabaseSetupStatus.ready);
      } else {
        // Check what version is available
        final version = await _dbService.checkForUpdate();
        state = state.copyWith(
          status: DatabaseSetupStatus.needsDownload,
          availableVersion: version,
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: DatabaseSetupStatus.error,
        errorMessage: 'Failed to check database: $e',
      );
    }
  }

  Future<void> downloadDatabase() async {
    state = state.copyWith(
      status: DatabaseSetupStatus.downloading,
      progress: 0.0,
    );

    _cancelToken = CancelToken();

    try {
      await _dbService.downloadDatabase(
        onProgress: (progress) {
          state = state.copyWith(progress: progress);
        },
        cancelToken: _cancelToken,
      );

      state = state.copyWith(status: DatabaseSetupStatus.ready);
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        state = state.copyWith(
          status: DatabaseSetupStatus.needsDownload,
        );
      } else {
        state = state.copyWith(
          status: DatabaseSetupStatus.error,
          errorMessage: 'Download failed: $e',
        );
      }
    }
  }

  void cancelDownload() {
    _cancelToken?.cancel();
    _cancelToken = null;
  }

  void retry() {
    checkDatabase();
  }
}

/// Screen shown when database needs to be downloaded
class DatabaseSetupScreen extends ConsumerStatefulWidget {
  final VoidCallback onComplete;

  const DatabaseSetupScreen({super.key, required this.onComplete});

  @override
  ConsumerState<DatabaseSetupScreen> createState() =>
      _DatabaseSetupScreenState();
}

class _DatabaseSetupScreenState extends ConsumerState<DatabaseSetupScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(databaseSetupProvider.notifier).checkDatabase();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(databaseSetupProvider);

    // Navigate to main app when ready
    ref.listen<DatabaseSetupState>(databaseSetupProvider, (previous, next) {
      if (next.status == DatabaseSetupStatus.ready) {
        widget.onComplete();
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // App icon
              Icon(
                Icons.gamepad_rounded,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Romgi',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'ROM Browser & Downloader',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
              const Spacer(),
              _buildContent(context, state),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, DatabaseSetupState state) {
    switch (state.status) {
      case DatabaseSetupStatus.checking:
        return Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Checking database...',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        );

      case DatabaseSetupStatus.ready:
        return Column(
          children: [
            Icon(
              Icons.check_circle,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Database ready!',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        );

      case DatabaseSetupStatus.needsDownload:
        return Column(
          children: [
            Icon(
              Icons.cloud_download,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Download ROM Database',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'The ROM catalog database needs to be downloaded to browse and search for games.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            if (state.availableVersion != null) ...[
              const SizedBox(height: 16),
              _buildVersionInfo(context, state.availableVersion!),
            ],
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {
                ref.read(databaseSetupProvider.notifier).downloadDatabase();
              },
              icon: const Icon(Icons.download),
              label: const Text('Download Database'),
            ),
          ],
        );

      case DatabaseSetupStatus.downloading:
        final progressPercent = (state.progress * 100).toInt();
        return Column(
          children: [
            const SizedBox(height: 24),
            Text(
              'Downloading database...',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '$progressPercent%',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 24),
            LinearProgressIndicator(
              value: state.progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () {
                ref.read(databaseSetupProvider.notifier).cancelDownload();
              },
              child: const Text('Cancel'),
            ),
          ],
        );

      case DatabaseSetupStatus.error:
        return Column(
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              'Download Failed',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              state.errorMessage ?? 'An error occurred',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {
                ref.read(databaseSetupProvider.notifier).retry();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        );
    }
  }

  Widget _buildVersionInfo(BuildContext context, DatabaseVersion version) {
    final sizeInMB = (version.size / 1024 / 1024).toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Download Size',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                '$sizeInMB MB',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ROM Entries',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                _formatNumber(version.entries),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Platforms',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                '${version.platforms}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }
}

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/download_service.dart';
import '../utils/utils.dart';
import 'internet_archive_login_screen.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadState = ref.watch(downloadProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          if (downloadState.completedDownloads.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'clear_completed') {
                  ref.read(downloadProvider.notifier).clearCompletedDownloads();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'clear_completed',
                  child: Text('Clear completed'),
                ),
              ],
            ),
        ],
      ),
      body: downloadState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(context, ref, downloadState),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    DownloadState state,
  ) {
    if (state.activeDownloads.isEmpty &&
        state.completedDownloads.isEmpty &&
        state.failedDownloads.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.download_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No downloads yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Browse ROMs and tap download to get started',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(downloadProvider.notifier).refresh(),
      child: ListView(
        children: [
          // Current downloads
          if (state.currentDownloads.isNotEmpty) ...[
            _SectionHeader(
              title: 'Downloading (${state.currentDownloads.length})',
            ),
            ...state.currentDownloads.map(
              (task) => _CurrentDownloadTile(task: task),
            ),
          ],

          // Queue
          if (state.queuedDownloads.isNotEmpty) ...[
            _SectionHeader(title: 'Queue (${state.queuedDownloads.length})'),
            ...state.queuedDownloads.map(
              (task) => _QueuedDownloadTile(task: task),
            ),
          ],

          // Failed
          if (state.failedDownloads.isNotEmpty) ...[
            _SectionHeader(title: 'Failed (${state.failedDownloads.length})'),
            ...state.failedDownloads.map(
              (task) => _FailedDownloadTile(task: task),
            ),
          ],

          // Completed
          if (state.completedDownloads.isNotEmpty) ...[
            _SectionHeader(
              title: 'Completed (${state.completedDownloads.length})',
            ),
            ...state.completedDownloads.map(
              (task) => _CompletedDownloadTile(task: task),
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _CurrentDownloadTile extends ConsumerWidget {
  final DownloadTask task;

  const _CurrentDownloadTile({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Box art
                SizedBox(
                  width: 48,
                  height: 48,
                  child: task.boxartUrl != null
                      ? CachedNetworkImage(
                          imageUrl: task.boxartUrl!,
                          fit: BoxFit.cover,
                          placeholder: (context, string) =>
                              const Icon(Icons.videogame_asset),
                          errorWidget: (context, string, error) =>
                              const Icon(Icons.videogame_asset),
                        )
                      : const Icon(Icons.videogame_asset, size: 32),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${PlatformNames.getDisplayName(task.platform)} • ${task.link.host} • ${task.statusText}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                // Pause button
                IconButton(
                  icon: const Icon(Icons.pause),
                  onPressed: () {
                    ref.read(downloadProvider.notifier).pauseDownload(task.id);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  task.progressText,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (task.speedText.isNotEmpty) ...[
                      Text(
                        task.speedText,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      '${(task.progress * 100).toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QueuedDownloadTile extends ConsumerWidget {
  final DownloadTask task;

  const _QueuedDownloadTile({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPaused = task.status == DownloadStatus.paused;

    return ListTile(
      leading: SizedBox(
        width: 40,
        height: 40,
        child: task.boxartUrl != null
            ? CachedNetworkImage(
                imageUrl: task.boxartUrl!,
                fit: BoxFit.cover,
                placeholder: (context, string) =>
                    const Icon(Icons.videogame_asset),
                errorWidget: (context, string, error) =>
                    const Icon(Icons.videogame_asset),
              )
            : const Icon(Icons.videogame_asset),
      ),
      title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${PlatformNames.getDisplayName(task.platform)} • ${task.link.sizeStr}${isPaused ? ' • Paused' : ''}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPaused)
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () {
                ref.read(downloadProvider.notifier).resumeDownload(task.id);
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.pause),
              onPressed: () {
                ref.read(downloadProvider.notifier).pauseDownload(task.id);
              },
            ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              ref.read(downloadProvider.notifier).cancelDownload(task.id);
            },
          ),
        ],
      ),
    );
  }
}

class _CompletedDownloadTile extends ConsumerWidget {
  final DownloadTask task;

  const _CompletedDownloadTile({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: SizedBox(
        width: 40,
        height: 40,
        child: task.boxartUrl != null
            ? CachedNetworkImage(
                imageUrl: task.boxartUrl!,
                fit: BoxFit.cover,
                placeholder: (context, string) =>
                    const Icon(Icons.videogame_asset),
                errorWidget: (context, string, error) =>
                    const Icon(Icons.videogame_asset),
              )
            : const Icon(Icons.videogame_asset),
      ),
      title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${PlatformNames.getDisplayName(task.platform)} • ${task.link.sizeStr}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle,
            color: Theme.of(context).colorScheme.primary,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Remove',
            onPressed: () {
              ref
                  .read(downloadProvider.notifier)
                  .removeCompletedDownload(task.id);
            },
          ),
        ],
      ),
    );
  }
}

class _FailedDownloadTile extends ConsumerWidget {
  final DownloadTask task;

  const _FailedDownloadTile({required this.task});

  bool get _isAuthRequired => DownloadService.isAuthRequiredError(task.error);

  String _getErrorMessage() {
    if (_isAuthRequired) {
      return 'Internet Archive login required';
    }
    return task.error ?? 'Download failed';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: SizedBox(
        width: 40,
        height: 40,
        child: task.boxartUrl != null
            ? CachedNetworkImage(
                imageUrl: task.boxartUrl!,
                fit: BoxFit.cover,
                placeholder: (context, string) =>
                    const Icon(Icons.videogame_asset),
                errorWidget: (context, string, error) =>
                    const Icon(Icons.videogame_asset),
              )
            : const Icon(Icons.videogame_asset),
      ),
      title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          if (_isAuthRequired)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                Icons.lock,
                size: 14,
                color: Colors.deepPurple.shade400,
              ),
            ),
          Expanded(
            child: Text(
              _getErrorMessage(),
              style: TextStyle(
                color: _isAuthRequired
                    ? Colors.deepPurple.shade400
                    : Theme.of(context).colorScheme.error,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isAuthRequired)
            TextButton.icon(
              icon: const Icon(Icons.lock_open, size: 18),
              label: const Text('Login'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.deepPurple.shade400,
              ),
              onPressed: () => _loginAndRetry(context, ref),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Retry',
              onPressed: () {
                ref.read(downloadProvider.notifier).retryDownload(task.id);
              },
            ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Remove',
            onPressed: () {
              ref.read(downloadProvider.notifier).cancelDownload(task.id);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _loginAndRetry(BuildContext context, WidgetRef ref) async {
    final loggedIn = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const InternetArchiveLoginScreen(),
      ),
    );

    if (loggedIn == true) {
      ref.invalidate(iaLoggedInProvider);
      ref.read(downloadProvider.notifier).retryDownload(task.id);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logged in! Retrying download...')),
        );
      }
    }
  }
}

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/providers.dart';
import '../services/rom_database_service.dart';
import '../services/storage_service.dart';
import '../utils/utils.dart';
import 'internet_archive_login_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final platformsAsync = ref.watch(platformsProvider);
    final storage = ref.watch(storageServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settings.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // Downloads Section
                _SectionHeader(title: 'Downloads'),

                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Concurrent Downloads'),
                  subtitle: Text(
                    settings.maxConcurrentDownloads == 0
                        ? 'Unlimited concurrent downloads'
                        : '${settings.maxConcurrentDownloads} download${settings.maxConcurrentDownloads == 1 ? '' : 's'} at a time',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text('1'),
                      Expanded(
                        child: Slider(
                          // Map: 0 (unlimited) displays at position 11, 1-10 display at 1-10
                          value: settings.maxConcurrentDownloads == 0
                              ? 11
                              : settings.maxConcurrentDownloads.toDouble(),
                          min: 1,
                          max: 11,
                          divisions: 10,
                          label: settings.maxConcurrentDownloads == 0
                              ? '∞'
                              : '${settings.maxConcurrentDownloads}',
                          onChanged: (value) {
                            // Map: position 11 saves as 0 (unlimited), 1-10 save as 1-10
                            final intValue = value.round();
                            ref
                                .read(settingsProvider.notifier)
                                .setMaxConcurrentDownloads(
                                  intValue > 10 ? 0 : intValue,
                                );
                          },
                        ),
                      ),
                      const Text('∞'),
                    ],
                  ),
                ),

                const Divider(height: 32),

                _SectionHeader(title: 'Download Locations'),

                FutureBuilder<String>(
                  future: storage.getDownloadDirectory().then((d) => d.path),
                  builder: (context, snapshot) {
                    final currentPath =
                        settings.defaultDownloadPath ??
                        snapshot.data ??
                        'Loading...';
                    return ListTile(
                      leading: const Icon(Icons.folder),
                      title: const Text('Default Location'),
                      subtitle: Text(
                        currentPath,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: settings.defaultDownloadPath != null
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                ref
                                    .read(settingsProvider.notifier)
                                    .setDefaultDownloadPath(null);
                              },
                            )
                          : null,
                      onTap: () => _pickFolder(context, ref, storage),
                    );
                  },
                ),

                const Divider(),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Platform-Specific Locations',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Override download location for specific platforms',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  ),
                ),
                const SizedBox(height: 8),
                platformsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, stackTrace) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Failed to load platforms',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                  data: (platforms) {
                    final sorted = List.of(platforms)
                      ..sort(
                        (a, b) => PlatformNames.getDisplayName(
                          a.id,
                        ).compareTo(PlatformNames.getDisplayName(b.id)),
                      );
                    return Column(
                      children: sorted.map((platform) {
                        final customPath = settings.platformPaths[platform.id];
                        return ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(
                            PlatformNames.getDisplayName(platform.id),
                          ),
                          subtitle: customPath != null
                              ? Text(
                                  customPath,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : const Text('Using default'),
                          trailing: customPath != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    ref
                                        .read(settingsProvider.notifier)
                                        .setPlatformPath(platform.id, null);
                                    storage.setPlatformPath(platform.id, null);
                                  },
                                )
                              : const Icon(Icons.chevron_right),
                          onTap: () => _pickFolder(
                            context,
                            ref,
                            storage,
                            platformId: platform.id,
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),

                const Divider(height: 32),

                _SectionHeader(title: 'Appearance'),

                ListTile(
                  leading: const Icon(Icons.brightness_6),
                  title: const Text('Theme'),
                  subtitle: Text(_getThemeModeName(settings.themeMode)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      _showThemePicker(context, ref, settings.themeMode),
                ),

                const Divider(height: 32),

                _SectionHeader(title: 'Library'),

                ListTile(
                  leading: const Icon(Icons.verified),
                  title: const Text('Verify Files'),
                  subtitle: const Text('Check if downloaded files still exist'),
                  onTap: () async {
                    await ref.read(libraryProvider.notifier).verifyFiles();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Files verified')),
                      );
                    }
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.cleaning_services),
                  title: const Text('Clean Up Library'),
                  subtitle: const Text('Remove entries for missing files'),
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Clean Up Library'),
                        content: const Text(
                          'Remove entries for files that no longer exist on disk?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Clean Up'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await ref
                          .read(libraryProvider.notifier)
                          .cleanupMissingFiles();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Library cleaned up')),
                        );
                      }
                    }
                  },
                ),

                const Divider(height: 32),

                _SectionHeader(title: 'Accounts'),

                _InternetArchiveAccountTile(),

                const Divider(height: 32),

                _SectionHeader(title: 'About'),

                const _VersionTile(),

                const _UpdateTile(),

                const _DatabaseInfoTile(),

                ListTile(
                  leading: const Icon(Icons.code),
                  title: const Text('Source Code'),
                  subtitle: const Text('github.com/caprado/romgi'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => launchUrl(
                    Uri.parse('https://github.com/caprado/romgi'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  String _getThemeModeName(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.system:
        return 'System default';
      case AppThemeMode.light:
        return 'Light';
      case AppThemeMode.dark:
        return 'Dark';
    }
  }

  void _showThemePicker(
    BuildContext context,
    WidgetRef ref,
    AppThemeMode currentMode,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Choose Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: AppThemeMode.values.map((mode) {
            final isSelected = mode == currentMode;
            return ListTile(
              leading: Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: isSelected
                    ? Theme.of(dialogContext).colorScheme.primary
                    : null,
              ),
              title: Text(_getThemeModeName(mode)),
              onTap: () {
                ref.read(settingsProvider.notifier).setThemeMode(mode);
                Navigator.pop(dialogContext);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _pickFolder(
    BuildContext context,
    WidgetRef ref,
    StorageService storage, {
    String? platformId,
  }) async {
    final result = await FilePicker.platform.getDirectoryPath();

    if (result != null) {
      if (platformId != null) {
        // Platform-specific path
        ref.read(settingsProvider.notifier).setPlatformPath(platformId, result);
        storage.setPlatformPath(platformId, result);
      } else {
        // Default path
        ref.read(settingsProvider.notifier).setDefaultDownloadPath(result);
        storage.setCustomDownloadPath(result);
      }
    }
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
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _VersionTile extends ConsumerWidget {
  const _VersionTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versionAsync = ref.watch(currentVersionProvider);

    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: const Text('Version'),
      subtitle: versionAsync.when(
        loading: () => const Text('Loading...'),
        error: (error, stackTrace) => const Text('Unknown'),
        data: (version) => Text(version),
      ),
    );
  }
}

class _UpdateTile extends ConsumerWidget {
  const _UpdateTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateState = ref.watch(updateProvider);

    return Column(
      children: [
        ListTile(
          leading: Icon(
            _getUpdateIcon(updateState.status),
            color: _getUpdateColor(context, updateState.status),
          ),
          title: Text(_getUpdateTitle(updateState.status)),
          subtitle: Text(_getUpdateSubtitle(updateState)),
          trailing: _buildTrailingWidget(context, ref, updateState),
          onTap:
              updateState.status == UpdateStatus.idle ||
                  updateState.status == UpdateStatus.error
              ? () => ref.read(updateProvider.notifier).checkForUpdate()
              : null,
        ),
        if (updateState.status == UpdateStatus.downloading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(value: updateState.downloadProgress),
          ),
      ],
    );
  }

  IconData _getUpdateIcon(UpdateStatus status) {
    switch (status) {
      case UpdateStatus.idle:
        return Icons.system_update;
      case UpdateStatus.checking:
        return Icons.refresh;
      case UpdateStatus.available:
        return Icons.download;
      case UpdateStatus.downloading:
        return Icons.downloading;
      case UpdateStatus.readyToInstall:
        return Icons.install_mobile;
      case UpdateStatus.error:
        return Icons.error_outline;
    }
  }

  Color? _getUpdateColor(BuildContext context, UpdateStatus status) {
    switch (status) {
      case UpdateStatus.available:
      case UpdateStatus.readyToInstall:
        return Theme.of(context).colorScheme.primary;
      case UpdateStatus.error:
        return Theme.of(context).colorScheme.error;
      default:
        return null;
    }
  }

  String _getUpdateTitle(UpdateStatus status) {
    switch (status) {
      case UpdateStatus.idle:
        return 'Check for Updates';
      case UpdateStatus.checking:
        return 'Checking for Updates...';
      case UpdateStatus.available:
        return 'Update Available';
      case UpdateStatus.downloading:
        return 'Downloading Update...';
      case UpdateStatus.readyToInstall:
        return 'Ready to Install';
      case UpdateStatus.error:
        return 'Update Check Failed';
    }
  }

  String _getUpdateSubtitle(UpdateState state) {
    switch (state.status) {
      case UpdateStatus.idle:
        return 'Tap to check for new versions';
      case UpdateStatus.checking:
        return 'Please wait...';
      case UpdateStatus.available:
        return 'Version ${state.availableUpdate?.version} is available';
      case UpdateStatus.downloading:
        final progress = (state.downloadProgress * 100).toInt();
        return 'Downloading... $progress%';
      case UpdateStatus.readyToInstall:
        return 'Tap Install to update to ${state.availableUpdate?.version}';
      case UpdateStatus.error:
        return state.errorMessage ?? 'An error occurred';
    }
  }

  Widget? _buildTrailingWidget(
    BuildContext context,
    WidgetRef ref,
    UpdateState state,
  ) {
    switch (state.status) {
      case UpdateStatus.checking:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case UpdateStatus.available:
        return ElevatedButton(
          onPressed: () => ref.read(updateProvider.notifier).downloadUpdate(),
          child: const Text('Download'),
        );
      case UpdateStatus.downloading:
        return IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => ref.read(updateProvider.notifier).cancelDownload(),
        );
      case UpdateStatus.readyToInstall:
        return ElevatedButton(
          onPressed: () => ref.read(updateProvider.notifier).installUpdate(),
          child: const Text('Install'),
        );
      case UpdateStatus.error:
        return IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.read(updateProvider.notifier).checkForUpdate(),
        );
      default:
        return const Icon(Icons.chevron_right);
    }
  }
}

class _InternetArchiveAccountTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggedInAsync = ref.watch(iaLoggedInProvider);
    final usernameAsync = ref.watch(iaUsernameProvider);

    return isLoggedInAsync.when(
      loading: () => const ListTile(
        leading: Icon(Icons.account_circle),
        title: Text('Internet Archive'),
        subtitle: Text('Checking...'),
      ),
      error: (error, stackTrace) => ListTile(
        leading: const Icon(Icons.account_circle),
        title: const Text('Internet Archive'),
        subtitle: const Text('Not logged in'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openLogin(context, ref),
      ),
      data: (isLoggedIn) {
        if (isLoggedIn) {
          final username = usernameAsync.valueOrNull ?? 'Unknown';
          return ListTile(
            leading: Icon(
              Icons.account_circle,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Internet Archive'),
            subtitle: Text('Logged in as $username'),
            trailing: TextButton(
              onPressed: () => _logout(context, ref),
              child: const Text('Logout'),
            ),
          );
        } else {
          return ListTile(
            leading: const Icon(Icons.account_circle),
            title: const Text('Internet Archive'),
            subtitle: const Text('Login to download protected files'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openLogin(context, ref),
          );
        }
      },
    );
  }

  void _openLogin(BuildContext context, WidgetRef ref) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const InternetArchiveLoginScreen(),
      ),
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text(
          'Are you sure you want to logout from Internet Archive?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final authService = ref.read(internetArchiveAuthProvider);
      await authService.logout();
      ref.invalidate(iaLoggedInProvider);
      ref.invalidate(iaUsernameProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logged out from Internet Archive')),
        );
      }
    }
  }
}

/// Provider to get local database version info
final localDbVersionProvider = FutureProvider<DatabaseVersion?>((ref) async {
  final dbService = ref.read(romDatabaseProvider);
  return dbService.getLocalVersion();
});

/// Provider to check for database updates
final dbUpdateAvailableProvider = FutureProvider<DatabaseVersion?>((ref) async {
  final dbService = ref.read(romDatabaseProvider);
  return dbService.checkForUpdate();
});

class _DatabaseInfoTile extends ConsumerWidget {
  const _DatabaseInfoTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localVersionAsync = ref.watch(localDbVersionProvider);
    final updateAvailableAsync = ref.watch(dbUpdateAvailableProvider);

    return localVersionAsync.when(
      loading: () => const ListTile(
        leading: Icon(Icons.storage),
        title: Text('ROM Database'),
        subtitle: Text('Loading...'),
      ),
      error: (error, stack) => ListTile(
        leading: const Icon(Icons.storage),
        title: const Text('ROM Database'),
        subtitle: const Text('Error loading database info'),
        trailing: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(localDbVersionProvider),
        ),
      ),
      data: (localVersion) {
        if (localVersion == null) {
          return ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('ROM Database'),
            subtitle: const Text('Not installed'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  onPressed: () => _showUpdateDialog(context, ref, null),
                  child: const Text('Download'),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'delete') {
                      _confirmDelete(context, ref);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline, color: Colors.red),
                        title: Text('Delete & Reset'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        final hasUpdate = updateAvailableAsync.valueOrNull != null;

        return ListTile(
          leading: Icon(
            Icons.storage,
            color: hasUpdate ? Theme.of(context).colorScheme.primary : null,
          ),
          title: const Text('ROM Database'),
          subtitle: Text(
            'Version ${localVersion.version} - ${_formatNumber(localVersion.entries)} entries',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasUpdate)
                FilledButton(
                  onPressed: () => _showUpdateDialog(
                    context,
                    ref,
                    updateAvailableAsync.valueOrNull,
                  ),
                  child: const Text('Update'),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    ref.invalidate(localDbVersionProvider);
                    ref.invalidate(dbUpdateAvailableProvider);
                  },
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'delete') {
                    _confirmDelete(context, ref);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline, color: Colors.red),
                      title: Text('Delete Database'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Database'),
        content: const Text(
          'This will delete the ROM database. You will need to download it again to browse ROMs.\n\nThis can help fix issues with a corrupted database.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final dbService = ref.read(romDatabaseProvider);
      await dbService.deleteDatabase();
      ref.invalidate(localDbVersionProvider);
      ref.invalidate(dbUpdateAvailableProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database deleted')),
        );
      }
    }
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(0)}K';
    }
    return number.toString();
  }

  void _showUpdateDialog(
    BuildContext context,
    WidgetRef ref,
    DatabaseVersion? newVersion,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _DatabaseUpdateDialog(newVersion: newVersion),
    ).then((_) {
      // Refresh providers after dialog closes
      ref.invalidate(localDbVersionProvider);
      ref.invalidate(dbUpdateAvailableProvider);
    });
  }
}

class _DatabaseUpdateDialog extends ConsumerStatefulWidget {
  final DatabaseVersion? newVersion;

  const _DatabaseUpdateDialog({this.newVersion});

  @override
  ConsumerState<_DatabaseUpdateDialog> createState() =>
      _DatabaseUpdateDialogState();
}

class _DatabaseUpdateDialogState extends ConsumerState<_DatabaseUpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isDownloading ? 'Updating Database' : 'Update Database'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 16),
          ],
          if (_isDownloading) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text('${(_progress * 100).toInt()}%'),
          ] else if (widget.newVersion != null) ...[
            Text(
              'A new database version is available.',
            ),
            const SizedBox(height: 8),
            Text(
              'Size: ${(widget.newVersion!.size / 1024 / 1024).toStringAsFixed(1)} MB',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else ...[
            const Text('Download the ROM database to browse and search games.'),
          ],
        ],
      ),
      actions: [
        if (!_isDownloading)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        if (!_isDownloading)
          FilledButton(
            onPressed: _startDownload,
            child: const Text('Download'),
          ),
      ],
    );
  }

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _error = null;
    });

    try {
      final dbService = RomDatabaseService();
      await dbService.downloadDatabase(
        onProgress: (progress) {
          setState(() {
            _progress = progress;
          });
        },
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database updated successfully')),
        );
      }
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _error = 'Download failed: $e';
      });
    }
  }
}

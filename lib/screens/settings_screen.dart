import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/providers.dart';
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

                // Download Locations Section
                _SectionHeader(title: 'Download Locations'),

                // Default download location
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

                // Per-platform locations
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
                  error: (error, _) => Padding(
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

                // Appearance Section
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

                // Library Section
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

                // Accounts Section
                _SectionHeader(title: 'Accounts'),

                _InternetArchiveAccountTile(),

                const Divider(height: 32),

                // About Section
                _SectionHeader(title: 'About'),

                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('romgi'),
                  subtitle: Text('Version 0.1.0'),
                ),

                const ListTile(
                  leading: Icon(Icons.storage),
                  title: Text('Data Source'),
                  subtitle: Text('CrocDB (api.crocdb.net)'),
                ),

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
      error: (_, __) => ListTile(
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

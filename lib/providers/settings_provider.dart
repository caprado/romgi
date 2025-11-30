import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { system, light, dark }

class SettingsState {
  final String? defaultDownloadPath;
  final Map<String, String> platformPaths; // platform -> custom path
  final AppThemeMode themeMode;
  final List<String> defaultPlatforms;
  final List<String> defaultRegions;
  final int maxConcurrentDownloads;
  final bool isLoading;

  const SettingsState({
    this.defaultDownloadPath,
    this.platformPaths = const {},
    this.themeMode = AppThemeMode.system,
    this.defaultPlatforms = const [],
    this.defaultRegions = const [],
    this.maxConcurrentDownloads = 3,
    this.isLoading = false,
  });

  SettingsState copyWith({
    String? defaultDownloadPath,
    bool clearDefaultPath = false,
    Map<String, String>? platformPaths,
    AppThemeMode? themeMode,
    List<String>? defaultPlatforms,
    List<String>? defaultRegions,
    int? maxConcurrentDownloads,
    bool? isLoading,
  }) {
    return SettingsState(
      defaultDownloadPath: clearDefaultPath ? null : (defaultDownloadPath ?? this.defaultDownloadPath),
      platformPaths: platformPaths ?? this.platformPaths,
      themeMode: themeMode ?? this.themeMode,
      defaultPlatforms: defaultPlatforms ?? this.defaultPlatforms,
      defaultRegions: defaultRegions ?? this.defaultRegions,
      maxConcurrentDownloads: maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  /// Get the download path for a platform (custom or default)
  String? getPathForPlatform(String platform) {
    return platformPaths[platform] ?? defaultDownloadPath;
  }

  /// Convert to Flutter ThemeMode
  ThemeMode get flutterThemeMode {
    switch (themeMode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  static const String _keyDefaultPath = 'default_download_path';
  static const String _keyPlatformPaths = 'platform_paths_';
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyDefaultPlatforms = 'default_platforms';
  static const String _keyDefaultRegions = 'default_regions';
  static const String _keyMaxConcurrentDownloads = 'max_concurrent_downloads';

  SettingsNotifier() : super(const SettingsState()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    state = state.copyWith(isLoading: true);

    final prefs = await SharedPreferences.getInstance();

    final defaultPath = prefs.getString(_keyDefaultPath);

    // Load theme mode
    final themeModeIndex = prefs.getInt(_keyThemeMode) ?? 0;
    final themeMode = AppThemeMode.values[themeModeIndex.clamp(0, AppThemeMode.values.length - 1)];

    // Load default filters
    final defaultPlatforms = prefs.getStringList(_keyDefaultPlatforms) ?? [];
    final defaultRegions = prefs.getStringList(_keyDefaultRegions) ?? [];

    // Load concurrent downloads setting
    final maxConcurrentDownloads = prefs.getInt(_keyMaxConcurrentDownloads) ?? 3;

    // Load platform-specific paths
    final platformPaths = <String, String>{};
    final keys = prefs.getKeys().where((k) => k.startsWith(_keyPlatformPaths));
    for (final key in keys) {
      final platform = key.replaceFirst(_keyPlatformPaths, '');
      final path = prefs.getString(key);
      if (path != null) {
        platformPaths[platform] = path;
      }
    }

    state = SettingsState(
      defaultDownloadPath: defaultPath,
      platformPaths: platformPaths,
      themeMode: themeMode,
      defaultPlatforms: defaultPlatforms,
      defaultRegions: defaultRegions,
      maxConcurrentDownloads: maxConcurrentDownloads,
      isLoading: false,
    );
  }

  Future<void> setDefaultDownloadPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();

    if (path == null) {
      await prefs.remove(_keyDefaultPath);
      state = state.copyWith(clearDefaultPath: true);
    } else {
      await prefs.setString(_keyDefaultPath, path);
      state = state.copyWith(defaultDownloadPath: path);
    }
  }

  Future<void> setPlatformPath(String platform, String? path) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_keyPlatformPaths$platform';

    final updatedPaths = Map<String, String>.from(state.platformPaths);

    if (path == null) {
      await prefs.remove(key);
      updatedPaths.remove(platform);
    } else {
      await prefs.setString(key, path);
      updatedPaths[platform] = path;
    }

    state = state.copyWith(platformPaths: updatedPaths);
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyThemeMode, mode.index);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setDefaultPlatforms(List<String> platforms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyDefaultPlatforms, platforms);
    state = state.copyWith(defaultPlatforms: platforms);
  }

  Future<void> setDefaultRegions(List<String> regions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyDefaultRegions, regions);
    state = state.copyWith(defaultRegions: regions);
  }

  Future<void> setMaxConcurrentDownloads(int value) async {
    final clamped = value.clamp(0, 10);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMaxConcurrentDownloads, clamped);
    state = state.copyWith(maxConcurrentDownloads: clamped);
  }

  Future<void> clearAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDefaultPath);
    await prefs.remove(_keyThemeMode);
    await prefs.remove(_keyDefaultPlatforms);
    await prefs.remove(_keyDefaultRegions);
    await prefs.remove(_keyMaxConcurrentDownloads);

    final keys = prefs.getKeys().where((k) => k.startsWith(_keyPlatformPaths));
    for (final key in keys) {
      await prefs.remove(key);
    }

    state = const SettingsState();
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});

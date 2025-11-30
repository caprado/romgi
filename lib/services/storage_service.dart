import 'dart:io';

import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class StorageService {
  static const String _defaultRomFolder = 'Roms';

  /// Default public storage path on Android
  static const String defaultAndroidPath = '/storage/emulated/0/Download/Roms';

  String? _customDownloadPath;
  Map<String, String> _platformPaths = {};

  /// Check if we have storage permission
  Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // Check for MANAGE_EXTERNAL_STORAGE on Android 11+
    final status = await Permission.manageExternalStorage.status;
    return status.isGranted;
  }

  /// Request storage permission
  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final status = await Permission.manageExternalStorage.request();
    return status.isGranted;
  }

  /// Open app settings for manual permission grant
  Future<void> openAppSettings() async {
    await openAppSettings();
  }

  /// Set platform-specific paths
  void setPlatformPaths(Map<String, String> paths) {
    _platformPaths = Map.from(paths);
  }

  /// Set a specific platform's custom path
  void setPlatformPath(String platform, String? path) {
    if (path == null) {
      _platformPaths.remove(platform);
    } else {
      _platformPaths[platform] = path;
    }
  }

  /// Get the base download directory
  Future<Directory> getDownloadDirectory() async {
    if (_customDownloadPath != null) {
      final customDir = Directory(_customDownloadPath!);
      if (!await customDir.exists()) {
        await customDir.create(recursive: true);
      }
      return customDir;
    }

    // On Android, use public Download/Roms folder
    if (Platform.isAndroid) {
      final downloadDir = Directory(defaultAndroidPath);
      try {
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        return downloadDir;
      } catch (e) {
        // Fall back to app-specific storage if permission denied
        final fallbackDir = await getExternalStorageDirectory();
        final romDir = Directory(p.join(fallbackDir!.path, _defaultRomFolder));
        if (!await romDir.exists()) {
          await romDir.create(recursive: true);
        }
        return romDir;
      }
    }

    // Non-Android platforms use documents directory
    final baseDir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory(p.join(baseDir.path, _defaultRomFolder));
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return downloadDir;
  }

  void setCustomDownloadPath(String? path) {
    _customDownloadPath = path;
  }

  /// Get the download directory for a specific platform
  Future<Directory> getPlatformDirectory(String platform) async {
    // Check for platform-specific custom path first
    if (_platformPaths.containsKey(platform)) {
      final customPath = _platformPaths[platform]!;
      final platformDir = Directory(customPath);
      if (!await platformDir.exists()) {
        await platformDir.create(recursive: true);
      }
      return platformDir;
    }

    // Fall back to base directory with platform subfolder
    final baseDir = await getDownloadDirectory();
    final platformDir = Directory(p.join(baseDir.path, platform));
    if (!await platformDir.exists()) {
      await platformDir.create(recursive: true);
    }
    return platformDir;
  }

  Future<String> getDownloadPath(String platform, String filename) async {
    final platformDir = await getPlatformDirectory(platform);
    return p.join(platformDir.path, filename);
  }

  Future<String> getCurrentPlatformPath(String platform) async {
    final dir = await getPlatformDirectory(platform);
    return dir.path;
  }

  Future<int> getAvailableSpace() async {
    try {
      final diskSpace = DiskSpacePlus();
      // disk_space_plus returns free space in MB
      final freeMB = await diskSpace.getFreeDiskSpace;
      if (freeMB == null || freeMB < 0) return -1;
      // Convert MB to bytes
      return (freeMB * 1024 * 1024).round();
    } catch (e) {
      return -1;
    }
  }

  Future<int> getTotalSpace() async {
    try {
      final diskSpace = DiskSpacePlus();
      final totalMB = await diskSpace.getTotalDiskSpace;
      if (totalMB == null || totalMB < 0) return -1;
      return (totalMB * 1024 * 1024).round();
    } catch (e) {
      return -1;
    }
  }

  Future<bool> deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> fileExists(String path) async {
    return File(path).exists();
  }

  Future<int> getFileSize(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        return await file.length();
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  Future<List<FileSystemEntity>> listDownloadedFiles() async {
    final dir = await getDownloadDirectory();
    final files = <FileSystemEntity>[];

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        files.add(entity);
      }
    }
    return files;
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

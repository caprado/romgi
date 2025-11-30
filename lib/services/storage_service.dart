import 'dart:io';

import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class StorageService {
  static const String _defaultRomFolder = 'romgi';

  String? _customDownloadPath;
  Map<String, String> _platformPaths = {};

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
      return Directory(_customDownloadPath!);
    }

    // Use external storage on Android, documents on other platforms
    Directory? baseDir;
    if (Platform.isAndroid) {
      baseDir = await getExternalStorageDirectory();
    }
    baseDir ??= await getApplicationDocumentsDirectory();

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

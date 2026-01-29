import 'dart:io';

import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class StorageService {
  static const String _defaultRomFolder = 'Roms';
  static const String defaultAndroidPath = '/storage/emulated/0/Download/Roms';

  String? _customDownloadPath;
  Map<String, String> _platformPaths = {};

  Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final status = await Permission.manageExternalStorage.status;

    return status.isGranted;
  }

  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final status = await Permission.manageExternalStorage.request();

    return status.isGranted;
  }

  Future<void> openAppSettings() async {
    await openAppSettings();
  }

  void setPlatformPaths(Map<String, String> paths) {
    _platformPaths = Map.from(paths);
  }

  void setPlatformPath(String platform, String? path) {
    if (path == null) {
      _platformPaths.remove(platform);
    } else {
      _platformPaths[platform] = path;
    }
  }

  Future<Directory> getDownloadDirectory() async {
    if (_customDownloadPath != null) {
      final customDirctory = Directory(_customDownloadPath!);
      if (!await customDirctory.exists()) {
        await customDirctory.create(recursive: true);
      }

      return customDirctory;
    }

    // On Android, use public Download/Roms folder
    if (Platform.isAndroid) {
      final downloadDirectory = Directory(defaultAndroidPath);
      try {
        if (!await downloadDirectory.exists()) {
          await downloadDirectory.create(recursive: true);
        }

        return downloadDirectory;
      } catch (error) {
        // Fall back to app-specific storage if permission denied
        final fallbackDirectory = await getExternalStorageDirectory();
        final romDirectory = Directory(
          path.join(fallbackDirectory!.path, _defaultRomFolder),
        );

        if (!await romDirectory.exists()) {
          await romDirectory.create(recursive: true);
        }

        return romDirectory;
      }
    }

    // Non-Android platforms use documents directory
    final baseDirectory = await getApplicationDocumentsDirectory();
    final downloadDir = Directory(
      path.join(baseDirectory.path, _defaultRomFolder),
    );
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }

    return downloadDir;
  }

  void setCustomDownloadPath(String? path) {
    _customDownloadPath = path;
  }

  Future<Directory> getPlatformDirectory(String platform) async {
    // Check for platform-specific custom path first
    if (_platformPaths.containsKey(platform)) {
      final customPath = _platformPaths[platform]!;
      final customPlatformDirectory = Directory(customPath);
      if (!await customPlatformDirectory.exists()) {
        await customPlatformDirectory.create(recursive: true);
      }

      return customPlatformDirectory;
    }

    // Fall back to base directory with platform subfolder
    final baseDirectory = await getDownloadDirectory();
    final defaultPlatformDirectory = Directory(
      path.join(baseDirectory.path, platform),
    );
    if (!await defaultPlatformDirectory.exists()) {
      await defaultPlatformDirectory.create(recursive: true);
    }

    return defaultPlatformDirectory;
  }

  Future<String> getDownloadPath(String platform, String filename) async {
    final platformDirectory = await getPlatformDirectory(platform);

    return path.join(platformDirectory.path, filename);
  }

  Future<String> getCurrentPlatformPath(String platform) async {
    final directory = await getPlatformDirectory(platform);

    return directory.path;
  }

  Future<int> getAvailableSpace() async {
    try {
      final diskSpace = DiskSpacePlus();
      final freeMB = await diskSpace.getFreeDiskSpace;

      if (freeMB == null || freeMB < 0) return -1;

      return (freeMB * 1024 * 1024).round();
    } catch (error) {
      return -1;
    }
  }

  /// TODO: Combine with getAvailableSpace if exact.
  Future<int> getTotalSpace() async {
    try {
      final diskSpace = DiskSpacePlus();
      final totalMB = await diskSpace.getTotalDiskSpace;

      if (totalMB == null || totalMB < 0) return -1;

      return (totalMB * 1024 * 1024).round();
    } catch (error) {
      return -1;
    }
  }

  Future<bool> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }

      try {
        await file.delete();
        return true;
      } catch (_) {}

      return false;
    } catch (_) {
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
    } catch (error) {
      return 0;
    }
  }

  Future<List<FileSystemEntity>> listDownloadedFiles() async {
    final directory = await getDownloadDirectory();
    final files = <FileSystemEntity>[];

    await for (final entity in directory.list(recursive: true)) {
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

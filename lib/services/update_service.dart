import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class AppRelease {
  final String version;
  final String tagName;
  final String? body;
  final String? apkDownloadUrl;
  final int? apkSize;
  final DateTime publishedAt;

  const AppRelease({
    required this.version,
    required this.tagName,
    this.body,
    this.apkDownloadUrl,
    this.apkSize,
    required this.publishedAt,
  });

  factory AppRelease.fromGitHubJson(Map<String, dynamic> json) {
    // Find the APK asset
    String? apkUrl;
    int? apkSize;
    final assets = json['assets'] as List<dynamic>? ?? [];
    for (final asset in assets) {
      final name = asset['name'] as String? ?? '';
      if (name.endsWith('.apk')) {
        apkUrl = asset['browser_download_url'] as String?;
        apkSize = asset['size'] as int?;
        break;
      }
    }

    // Parse version from tag (remove 'v' prefix if present)
    final tagName = json['tag_name'] as String? ?? '';
    final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;

    return AppRelease(
      version: version,
      tagName: tagName,
      body: json['body'] as String?,
      apkDownloadUrl: apkUrl,
      apkSize: apkSize,
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class UpdateService {
  static const String _githubRepo = 'caprado/romgi';
  static const String _releasesUrl =
      'https://api.github.com/repos/$_githubRepo/releases/latest';

  final Dio _dio;

  UpdateService({Dio? dio}) : _dio = dio ?? Dio();

  /// Get the current app version
  Future<String> getCurrentVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  /// Fetch the latest release from GitHub
  Future<AppRelease?> getLatestRelease() async {
    try {
      final response = await _dio.get(
        _releasesUrl,
        options: Options(
          headers: {
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'romgi-app',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        return AppRelease.fromGitHubJson(response.data as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Check if an update is available
  Future<AppRelease?> checkForUpdate() async {
    final currentVersion = await getCurrentVersion();
    final latestRelease = await getLatestRelease();

    if (latestRelease == null) return null;

    if (_isNewerVersion(latestRelease.version, currentVersion)) {
      return latestRelease;
    }
    return null;
  }

  /// Compare version strings (e.g., "1.0.1" > "1.0.0")
  bool _isNewerVersion(String newVersion, String currentVersion) {
    final newParts = newVersion.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final currentParts = currentVersion.split('.').map((p) => int.tryParse(p) ?? 0).toList();

    // Pad shorter list with zeros
    while (newParts.length < currentParts.length) {
      newParts.add(0);
    }
    while (currentParts.length < newParts.length) {
      currentParts.add(0);
    }

    for (var i = 0; i < newParts.length; i++) {
      if (newParts[i] > currentParts[i]) return true;
      if (newParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  /// Download the APK update
  Future<String?> downloadUpdate(
    AppRelease release, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (release.apkDownloadUrl == null) return null;

    try {
      final tempDir = await getTemporaryDirectory();
      final apkPath = '${tempDir.path}/romgi-${release.version}.apk';

      await _dio.download(
        release.apkDownloadUrl!,
        apkPath,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            'User-Agent': 'romgi-app',
          },
        ),
      );

      return apkPath;
    } catch (e) {
      return null;
    }
  }

  /// Install the downloaded APK
  Future<bool> installApk(String apkPath) async {
    try {
      final result = await OpenFilex.open(apkPath);
      return result.type == ResultType.done;
    } catch (e) {
      return false;
    }
  }
}

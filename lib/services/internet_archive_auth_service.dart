import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class InternetArchiveAuthService {
  static const String _storageKeyPrefix = 'ia_cookie_';
  static const String _storageKeyLoggedIn = 'ia_logged_in';
  static const String _storageKeyUsername = 'ia_username';

  static const List<String> _requiredCookies = [
    'logged-in-user',
    'logged-in-sig',
  ];

  static const List<String> _allCookies = [
    'ia-auth',
    'logged-in-sig',
    'logged-in-user',
    'PHPSESSID',
  ];

  final FlutterSecureStorage _storage;

  InternetArchiveAuthService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  Future<bool> isLoggedIn() async {
    try {
      final loggedIn = await _storage.read(key: _storageKeyLoggedIn);
      if (loggedIn != 'true') return false;

      // Verify we have the required cookies
      for (final cookie in _requiredCookies) {
        final value = await _storage.read(key: '$_storageKeyPrefix$cookie');
        if (value == null || value.isEmpty) return false;
      }
      return true;
    } catch (error) {
      // Handle platform exceptions gracefully
      return false;
    }
  }

  Future<String?> getUsername() async {
    try {
      return await _storage.read(key: _storageKeyUsername);
    } catch (error) {
      return null;
    }
  }

  Future<void> saveCookies(Map<String, String> cookies) async {
    try {
      for (final entry in cookies.entries) {
        if (_allCookies.contains(entry.key)) {
          await _storage.write(
            key: '$_storageKeyPrefix${entry.key}',
            value: entry.value,
          );
        }
      }

      // Extract username from logged-in-user cookie
      final username = cookies['logged-in-user'];
      if (username != null && username.isNotEmpty) {
        await _storage.write(key: _storageKeyUsername, value: username);
        await _storage.write(key: _storageKeyLoggedIn, value: 'true');
      }
    } catch (error) {
      // Ignore storage errors
    }
  }

  Future<String?> getCookieHeader() async {
    try {
      final isAuth = await isLoggedIn();
      if (!isAuth) return null;

      final cookies = <String>[];
      for (final cookieName in _allCookies) {
        final value = await _storage.read(key: '$_storageKeyPrefix$cookieName');
        if (value != null && value.isNotEmpty) {
          cookies.add('$cookieName=$value');
        }
      }

      return cookies.isNotEmpty ? cookies.join('; ') : null;
    } catch (error) {
      return null;
    }
  }

  Future<Map<String, String>> getCookiesMap() async {
    try {
      final cookies = <String, String>{};
      for (final cookieName in _allCookies) {
        final value = await _storage.read(key: '$_storageKeyPrefix$cookieName');
        if (value != null && value.isNotEmpty) {
          cookies[cookieName] = value;
        }
      }

      return cookies;
    } catch (error) {
      return {};
    }
  }

  Future<void> logout() async {
    try {
      for (final cookieName in _allCookies) {
        await _storage.delete(key: '$_storageKeyPrefix$cookieName');
      }

      await _storage.delete(key: _storageKeyLoggedIn);
      await _storage.delete(key: _storageKeyUsername);
    } catch (error) {
      // Ignore storage errors
    }
  }

  /// Check if a download link requires Internet Archive login
  /// Checks the link type field for patterns like "Game (Encrypted) (Requires Internet Archive Log in)"
  static bool requiresLogin(String linkType) {
    final lower = linkType.toLowerCase();

    return lower.contains('requires internet archive') ||
        lower.contains('requires login') ||
        lower.contains('(encrypted)');
  }

  static bool isInternetArchiveUrl(String url) {
    return url.contains('archive.org');
  }
}

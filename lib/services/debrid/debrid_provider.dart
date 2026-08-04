library;

class DebridProviderInfo {
  final String id;
  final String name;
  final String apiKeyHelp;

  const DebridProviderInfo({
    required this.id,
    required this.name,
    this.apiKeyHelp = '',
  });
}

class DebridFileRequest {
  final String infohash;
  final String magnet;
  final int fileIndex;
  final String? filePath;
  final int expectedSize;

  const DebridFileRequest({
    required this.infohash,
    required this.magnet,
    required this.fileIndex,
    this.filePath,
    this.expectedSize = 0,
  });
}

sealed class DebridResult {
  const DebridResult();
}

class DebridReady extends DebridResult {
  final String url;
  final String? filename;
  final int? size;

  const DebridReady(this.url, {this.filename, this.size});
}

class DebridCaching extends DebridResult {
  final double? progress;
  final Duration? retryAfter;

  const DebridCaching({this.progress, this.retryAfter});
}
class DebridNotCached extends DebridResult {
  const DebridNotCached();
}

class DebridError extends DebridResult {
  final String message;
  final bool authError;
  final bool rateLimited;

  /// Retrying cannot help — the poll loop aborts instead of spinning.
  final bool permanent;

  const DebridError(
    this.message, {
    this.authError = false,
    this.rateLimited = false,
    this.permanent = false,
  });
}

abstract class DebridProvider {
  DebridProviderInfo get info;

  bool isConfigured(String? apiKey);

  Future<String?> validateKey(String apiKey);

  Future<DebridResult> resolveFile(
    DebridFileRequest req, {
    required String apiKey,
  });
}

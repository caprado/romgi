library;

class MetadataProviderInfo {
  final String id;
  final String name;

  const MetadataProviderInfo({required this.id, required this.name});
}

class CredentialField {
  final String key;
  final String label;
  final bool obscure;
  final bool optional;

  const CredentialField({
    required this.key,
    required this.label,
    this.obscure = false,
    this.optional = false,
  });
}

sealed class MetadataResult {
  const MetadataResult();
}

class MetadataFound extends MetadataResult {
  final String? description;
  final List<String> screenshotUrls;
  final List<String> artworkUrls;

  const MetadataFound({
    this.description,
    this.screenshotUrls = const [],
    this.artworkUrls = const [],
  });
}

class MetadataNoMatch extends MetadataResult {
  const MetadataNoMatch();
}

class MetadataError extends MetadataResult {
  final String message;
  final bool authError;

  const MetadataError(this.message, {this.authError = false});
}

abstract class GameMetadataProvider {
  MetadataProviderInfo get info;

  List<CredentialField> get credentialFields;

  bool isConfigured(Map<String, String>? creds) {
    if (creds == null) return false;
    for (final field in credentialFields) {
      if (field.optional) continue;
      if ((creds[field.key] ?? '').trim().isEmpty) return false;
    }
    return true;
  }

  Future<String?> validateCredentials(Map<String, String> creds);

  Future<MetadataResult> fetch({
    required String title,
    required String platform,
    required Map<String, String> creds,
  });
}

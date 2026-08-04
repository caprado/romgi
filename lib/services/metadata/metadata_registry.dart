import 'metadata_provider.dart';
import 'screenscraper_provider.dart';
import 'steamgriddb_provider.dart';

class MetadataProviderRegistry {
  MetadataProviderRegistry({List<GameMetadataProvider>? providers})
      : _providers =
            providers ?? [ScreenScraperProvider(), SteamGridDbProvider()];

  final List<GameMetadataProvider> _providers;

  List<GameMetadataProvider> get providers => _providers;

  List<MetadataProviderInfo> get available =>
      _providers.map((provider) => provider.info).toList(growable: false);

  GameMetadataProvider? byId(String? id) {
    if (id == null) return null;
    for (final provider in _providers) {
      if (provider.info.id == id) return provider;
    }
    return null;
  }
}

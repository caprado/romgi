import 'debrid_provider.dart';
import 'realdebrid_provider.dart';
import 'torbox_provider.dart';

/// The set of debrid providers the app knows about. Adding a provider is a
/// one-line change to the default list — nothing else in the pipeline needs
/// editing (mirrors the grouping-strategy registry in db/grouping).
class DebridProviderRegistry {
  DebridProviderRegistry({List<DebridProvider>? providers})
      : _providers = providers ?? [TorboxProvider(), RealDebridProvider()];

  final List<DebridProvider> _providers;

  /// Descriptors for the settings picker (no network, no key needed).
  List<DebridProviderInfo> get available =>
      _providers.map((provider) => provider.info).toList(growable: false);

  DebridProvider? byId(String? id) {
    if (id == null) return null;
    for (final provider in _providers) {
      if (provider.info.id == id) return provider;
    }
    return null;
  }

  DebridProvider get defaultProvider => _providers.first;
}

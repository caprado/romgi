import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/debrid_service.dart';
import 'api_provider.dart';
import 'settings_provider.dart';

final debridServiceProvider = Provider<DebridService>((ref) {
  final romDb = ref.watch(romDatabaseProvider);
  final service = DebridService(romDb: romDb);
  service.getSelectedProviderId =
      () => ref.read(settingsProvider).debridProviderId;
  return service;
});

final debridConfiguredProvider = FutureProvider<bool>((ref) async {
  // Recompute when the selected provider changes.
  ref.watch(settingsProvider.select((s) => s.debridProviderId));
  return ref.watch(debridServiceProvider).isConfigured();
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/game_metadata_service.dart';
import 'api_provider.dart';
import 'download_provider.dart';
import 'settings_provider.dart';

final gameMetadataServiceProvider = Provider<GameMetadataService>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return GameMetadataService(db: db);
});

final metadataConfiguredProvider = FutureProvider<bool>((ref) {
  return ref.watch(gameMetadataServiceProvider).anyConfigured();
});

final metadataProviderConfiguredProvider =
    FutureProvider.family<bool, String>((ref, providerId) {
  return ref.watch(gameMetadataServiceProvider).isConfigured(providerId);
});

final gameMetadataProvider =
    FutureProvider.autoDispose.family<GameMetadata?, String>((ref, slug) async {
  if (!ref.watch(settingsProvider.select((s) => s.metadataEnabled))) {
    return null;
  }
  final entry = await ref.watch(romDatabaseProvider).getEntry(slug);
  if (entry == null) return null;
  return ref.watch(gameMetadataServiceProvider).getMetadata(entry);
});

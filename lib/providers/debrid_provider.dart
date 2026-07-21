import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/debrid_service.dart';
import 'api_provider.dart';

final debridServiceProvider = Provider<DebridService>((ref) {
  final romDb = ref.watch(romDatabaseProvider);
  return DebridService(romDb: romDb);
});

final debridConfiguredProvider = FutureProvider<bool>((ref) async {
  return ref.watch(debridServiceProvider).isConfigured();
});

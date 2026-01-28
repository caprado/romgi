import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'api_provider.dart';

final platformsProvider = FutureProvider<List<Platform>>((ref) async {
  final db = ref.watch(romDatabaseProvider);

  return db.getPlatforms();
});

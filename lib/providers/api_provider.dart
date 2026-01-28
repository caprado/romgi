import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/rom_database_service.dart';

/// Provider for the ROM database service (local SQLite database)
final romDatabaseProvider = Provider<RomDatabaseService>((ref) {
  return RomDatabaseService();
});

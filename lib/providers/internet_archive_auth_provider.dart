import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/services.dart';

final internetArchiveAuthProvider = Provider<InternetArchiveAuthService>((ref) {
  return InternetArchiveAuthService();
});

final iaLoggedInProvider = FutureProvider<bool>((ref) async {
  final authService = ref.watch(internetArchiveAuthProvider);

  return authService.isLoggedIn();
});

final iaUsernameProvider = FutureProvider<String?>((ref) async {
  final authService = ref.watch(internetArchiveAuthProvider);

  return authService.getUsername();
});

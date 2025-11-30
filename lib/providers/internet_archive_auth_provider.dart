import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/services.dart';

/// Provider for the Internet Archive auth service
final internetArchiveAuthProvider = Provider<InternetArchiveAuthService>((ref) {
  return InternetArchiveAuthService();
});

/// Provider to check if user is logged in to Internet Archive
final iaLoggedInProvider = FutureProvider<bool>((ref) async {
  final authService = ref.watch(internetArchiveAuthProvider);
  return authService.isLoggedIn();
});

/// Provider to get the logged-in username
final iaUsernameProvider = FutureProvider<String?>((ref) async {
  final authService = ref.watch(internetArchiveAuthProvider);
  return authService.getUsername();
});

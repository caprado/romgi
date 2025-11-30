import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import 'api_provider.dart';

final regionsProvider = FutureProvider<List<Region>>((ref) async {
  final api = ref.watch(crocDbApiProvider);
  return api.getRegions();
});

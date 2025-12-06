import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/crocdb_api.dart';

final crocDbApiProvider = Provider<CrocDbApi>((ref) {
  return CrocDbApi();
});

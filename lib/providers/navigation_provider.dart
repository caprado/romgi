import 'package:flutter_riverpod/flutter_riverpod.dart';

class NavTab {
  static const int browse = 0;
  static const int downloads = 1;
  static const int library = 2;
  static const int settings = 3;
}

final navigationTabProvider = StateProvider<int>((ref) => NavTab.browse);

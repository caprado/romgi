class RegionUtils {
  static const _hiddenRegions = {'other', 'unknown', 'unk'};

  static String getFlag(String region) {
    final lower = region.toLowerCase();

    return switch (lower) {
      'us' || 'usa' || 'america' => '🇺🇸',
      'eu' || 'europe' || 'eur' => '🇪🇺',
      'jp' || 'japan' || 'jpn' => '🇯🇵',
      'world' || 'wld' || 'global' => '🌐',
      _ => '🌍', // Default globe for unknown regions
    };
  }

  static bool shouldHide(String region) {
    return _hiddenRegions.contains(region.toLowerCase());
  }

  static String getFlagWithCode(String region) {
    if (shouldHide(region)) {
      return '🌍';
    }

    return '${getFlag(region)} ${region.toUpperCase()}';
  }

  static String getFlags(List<String> regions) {
    final visible = regions.where((region) => !shouldHide(region)).toList();
    if (visible.isEmpty && regions.isNotEmpty) {
      // If all regions were hidden, show a globe
      return '🌍';
    }

    return visible.map(getFlag).join('');
  }

  static List<String> filterRegions(List<String> regions) {
    return regions.where((region) => !shouldHide(region)).toList();
  }
}

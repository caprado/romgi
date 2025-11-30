/// Utility class for region-related functionality
class RegionUtils {
  /// Regions that should be hidden from display (use globe instead)
  static const _hiddenRegions = {'other', 'unknown', 'unk'};

  /// Get flag emoji for a region code
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

  /// Check if a region should be hidden (e.g., "other")
  static bool shouldHide(String region) {
    return _hiddenRegions.contains(region.toLowerCase());
  }

  /// Get flag emoji with region code (e.g., "🇺🇸 US")
  /// Returns just globe for hidden regions
  static String getFlagWithCode(String region) {
    if (shouldHide(region)) {
      return '🌍';
    }
    return '${getFlag(region)} ${region.toUpperCase()}';
  }

  /// Get just the flags for a list of regions (e.g., "🇺🇸🇪🇺🇯🇵")
  /// Filters out hidden regions like "other"
  static String getFlags(List<String> regions) {
    final visible = regions.where((r) => !shouldHide(r)).toList();
    if (visible.isEmpty && regions.isNotEmpty) {
      // If all regions were hidden, show a globe
      return '🌍';
    }
    return visible.map(getFlag).join('');
  }

  /// Filter out hidden regions from a list
  static List<String> filterRegions(List<String> regions) {
    return regions.where((r) => !shouldHide(r)).toList();
  }
}

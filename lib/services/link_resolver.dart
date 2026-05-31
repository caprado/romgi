import '../models/download_link.dart';

/// User-controllable preferences that influence link ranking.
class LinkResolverPrefs {
  /// Source ids the user has disabled. Disabled sources are dropped
  /// from the list entirely.
  final Set<String> disabledSourceIds;

  /// Source ids the user has marked preferred. Higher rank.
  final Set<String> preferredSourceIds;

  /// When false, links with `requires_auth` and an IA host are dropped
  /// rather than just sunk in the ranking.
  final bool isIaLoggedIn;

  /// When true, torrent links are dropped entirely.
  final bool torrentsDisabled;

  const LinkResolverPrefs({
    this.disabledSourceIds = const {},
    this.preferredSourceIds = const {},
    this.isIaLoggedIn = false,
    this.torrentsDisabled = false,
  });
}

class ResolvedLink {
  final DownloadLink link;

  /// Higher scores rank earlier. Composed of source priority, login
  /// state, and delivery mode preferences.
  final int score;

  /// Reason the link was demoted, if any. Useful for surfacing in UI
  /// (e.g. "needs login").
  final String? notice;

  const ResolvedLink({required this.link, required this.score, this.notice});
}

class LinkResolver {
  /// Default per-source priority for links whose source manifest hasn't
  /// loaded yet (or where source_id is missing on older catalog rows).
  static const int _fallbackPriority = 0;

  /// Map of source id → manifest priority. Populated by SourcesService.
  final Map<String, int> sourcePriority;

  const LinkResolver({this.sourcePriority = const {}});

  /// Returns links ranked best-first. Auth-required links are pushed
  /// down (or removed) when the user isn't logged in. Unknown / disabled
  /// sources are removed entirely.
  List<ResolvedLink> rank(
    List<DownloadLink> links,
    LinkResolverPrefs prefs,
  ) {
    final out = <ResolvedLink>[];
    for (final link in links) {
      final sourceId = link.sourceId;

      if (sourceId != null && prefs.disabledSourceIds.contains(sourceId)) {
        continue;
      }

      if (link.isTorrent && prefs.torrentsDisabled) {
        continue;
      }

      final needsAuth = link.requiresAuth;
      if (needsAuth && !prefs.isIaLoggedIn) {
        out.add(ResolvedLink(
          link: link,
          score: -100,
          notice: 'Internet Archive login required',
        ));
        continue;
      }

      var score = sourcePriority[sourceId] ?? _fallbackPriority;
      if (sourceId != null && prefs.preferredSourceIds.contains(sourceId)) {
        score += 1000;
      }
      // HTTP first when other factors are equal — torrents have lifecycle
      // overhead (peer discovery, piece overhead) that HTTP avoids.
      if (!link.isTorrent) score += 1;

      out.add(ResolvedLink(link: link, score: score));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }
}

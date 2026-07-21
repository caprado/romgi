import '../models/download_link.dart';

class LinkResolverPrefs {
  final Set<String> disabledSourceIds;
  final Set<String> preferredSourceIds;
  final bool isIaLoggedIn;
  final bool torrentsDisabled;
  final bool debridEnabled;

  const LinkResolverPrefs({
    this.disabledSourceIds = const {},
    this.preferredSourceIds = const {},
    this.isIaLoggedIn = false,
    this.torrentsDisabled = false,
    this.debridEnabled = false,
  });
}

class ResolvedLink {
  final DownloadLink link;
  final int score;
  final String? notice;

  const ResolvedLink({required this.link, required this.score, this.notice});
}

class LinkResolver {
  static const int _fallbackPriority = 0;

  final Map<String, int> sourcePriority;

  const LinkResolver({this.sourcePriority = const {}});

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

      if (link.isTorrent && prefs.torrentsDisabled && !prefs.debridEnabled) {
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

      if (!link.isTorrent || prefs.debridEnabled) score += 1;

      out.add(ResolvedLink(link: link, score: score));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }
}

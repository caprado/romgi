import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/download_service.dart';
import '../services/link_resolver.dart';
import '../utils/utils.dart';
import '../widgets/widgets.dart';
import 'internet_archive_login_screen.dart';

final entryProvider = FutureProvider.family<RomEntry?, String>((
  ref,
  slug,
) async {
  final db = ref.watch(romDatabaseProvider);

  return db.getEntry(slug);
});

/// The group an entry belongs to (e.g. its multi-disc set), or null.
final entryGroupProvider = FutureProvider.family<EntryGroup?, String>((
  ref,
  slug,
) async {
  final db = ref.watch(romDatabaseProvider);

  return db.getEntryGroup(slug);
});

// Mirror of source.yml priority values. Replaced when the SourcesService
// surfaces the live manifest table.
const Map<String, int> kKnownSourcePriority = {
  'minerva': 200,
  'nopaystation': 80,
  'mariocube': 70,
  'internet_archive': 50,
};

class EntryDetailScreen extends ConsumerWidget {
  final String slug;

  const EntryDetailScreen({super.key, required this.slug});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entryAsync = ref.watch(entryProvider(slug));

    return Scaffold(
      body: entryAsync.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (error, stack) => Scaffold(
          appBar: AppBar(),
          body: ErrorView(
            error: error,
            onRetry: () => ref.invalidate(entryProvider(slug)),
          ),
        ),
        data: (entry) => entry == null
            ? Scaffold(
                appBar: AppBar(),
                body: const Center(child: Text('Entry not found')),
              )
            : _EntryDetailContent(entry: entry),
      ),
    );
  }
}

class _EntryDetailContent extends ConsumerStatefulWidget {
  final RomEntry entry;

  const _EntryDetailContent({required this.entry});

  @override
  ConsumerState<_EntryDetailContent> createState() =>
      _EntryDetailContentState();
}

class _EntryDetailContentState extends ConsumerState<_EntryDetailContent> {
  final ScrollController _scrollController = ScrollController();
  bool _isCollapsed = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // Track this entry as recently viewed
    WidgetsBinding.instance.addPostFrameCallback((debugLabel) {
      ref
          .read(recentlyViewedProvider.notifier)
          .addEntry(
            slug: widget.entry.slug,
            title: widget.entry.title,
            platform: widget.entry.platform,
            boxartUrl: widget.entry.boxartUrl,
          );
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Calculate when the app bar is mostly collapsed
    // Consider collapsed when scrolled past 80% of that
    final scrollThreshold = 200.0;
    final isNowCollapsed = _scrollController.offset > scrollThreshold;

    if (isNowCollapsed != _isCollapsed) {
      setState(() {
        _isCollapsed = isNowCollapsed;
      });
    }
  }

  List<DownloadLink> _rankLinks(
    List<DownloadLink> links, {
    required bool iaLoggedIn,
    required bool torrentsDisabled,
  }) {
    final resolver = LinkResolver(sourcePriority: kKnownSourcePriority);
    final ranked = resolver.rank(
      links,
      LinkResolverPrefs(
        isIaLoggedIn: iaLoggedIn,
        torrentsDisabled: torrentsDisabled,
      ),
    );
    return ranked.map((r) => r.link).toList();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final isDownloadedAsync = ref.watch(isDownloadedProvider(entry.slug));
    final hasBoxart = entry.boxartUrl != null;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // Collapsing app bar with box art
        SliverAppBar(
          expandedHeight: hasBoxart ? 300 : 0,
          pinned: true,
          // Dynamic icon styling based on scroll position
          iconTheme: hasBoxart && !_isCollapsed
              ? const IconThemeData(color: Colors.white)
              : null,
          actions: [
            _FavoriteButton(
              entry: entry,
              isCollapsed: _isCollapsed,
              hasBoxart: hasBoxart,
            ),
          ],
          flexibleSpace: hasBoxart
              ? FlexibleSpaceBar(
                  title: Text(
                    entry.title,
                    style: TextStyle(
                      fontSize: 14,
                      color: _isCollapsed
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.white,
                      shadows: _isCollapsed
                          ? null
                          : const [
                              Shadow(color: Colors.black, blurRadius: 4),
                              Shadow(color: Colors.black, blurRadius: 8),
                            ],
                    ),
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: entry.boxartUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.broken_image, size: 64),
                        ),
                      ),
                      // Top gradient for back button visibility
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.center,
                            colors: [Colors.black54, Colors.transparent],
                          ),
                        ),
                      ),
                      // Bottom gradient for title visibility
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.center,
                            colors: [Colors.black54, Colors.transparent],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : FlexibleSpaceBar(title: Text(entry.title)),
        ),

        // Content
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Already downloaded badge
              isDownloadedAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (error, stackTrace) => const SizedBox.shrink(),
                data: (isDownloaded) => isDownloaded
                    ? Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Already downloaded',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              // Platform and regions
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(
                    icon: Icons.videogame_asset,
                    label: PlatformNames.getDisplayName(entry.platform),
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    foregroundColor: Theme.of(
                      context,
                    ).colorScheme.onPrimaryContainer,
                  ),
                  ...RegionUtils.filterRegions(entry.regions).map(
                    (region) => _RegionChip(
                      region: region,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.secondaryContainer,
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onSecondaryContainer,
                    ),
                  ),
                  if (entry.hasRetroAchievements)
                    _InfoChip(
                      icon: Icons.emoji_events,
                      label: entry.raNumAchievements != null
                          ? '${entry.raNumAchievements} achievements'
                          : 'RetroAchievements',
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onPrimaryContainer,
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Multi-disc set: offer to grab every disc + build an .m3u.
              ref.watch(entryGroupProvider(entry.slug)).maybeWhen(
                    data: (group) =>
                        (group != null && group.isDisc && group.members.length > 1)
                            ? _DiscGroupSection(entry: entry, group: group)
                            : const SizedBox.shrink(),
                    orElse: () => const SizedBox.shrink(),
                  ),

              ref.watch(gameMetadataProvider(entry.slug)).maybeWhen(
                    data: (metadata) => (metadata == null || metadata.isEmpty)
                        ? const SizedBox.shrink()
                        : _MetadataCard(metadata: metadata),
                    orElse: () => const SizedBox.shrink(),
                  ),

              // Download links header
              Row(
                children: [
                  Icon(
                    Icons.download,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Download Links',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  ...() {
                    final ranked = _rankLinks(
                      entry.links,
                      iaLoggedIn: ref.watch(iaLoggedInProvider).maybeWhen(
                            data: (loggedIn) => loggedIn,
                            orElse: () => false,
                          ),
                      torrentsDisabled:
                          ref.watch(settingsProvider).torrentsDisabled,
                    );
                    return [
                      Text(
                        '${ranked.length} available',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ];
                  }(),
                ],
              ),
              const SizedBox(height: 12),

              // Download links
              ...() {
                final ranked = _rankLinks(
                  entry.links,
                  iaLoggedIn: ref.watch(iaLoggedInProvider).maybeWhen(
                        data: (loggedIn) => loggedIn,
                        orElse: () => false,
                      ),
                  torrentsDisabled:
                      ref.watch(settingsProvider).torrentsDisabled,
                );
                if (ranked.isEmpty && entry.links.isEmpty) {
                  return [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(
                              Icons.cloud_off,
                              size: 48,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(height: 8),
                            const Text('No download links available'),
                          ],
                        ),
                      ),
                    ),
                  ];
                }
                if (ranked.isEmpty) {
                  return [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(
                              Icons.block,
                              size: 48,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'All download links are torrents.\nEnable torrents in Settings to download.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ];
                }
                return ranked
                    .map((link) => _DownloadLinkCard(entry: entry, link: link))
                    .toList();
              }(),

              const SizedBox(height: 32),
            ]),
          ),
        ),
      ],
    );
  }
}

class _DiscGroupSection extends ConsumerWidget {
  final RomEntry entry;
  final EntryGroup group;

  const _DiscGroupSection({required this.entry, required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.album, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '${group.members.length}-disc game',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Download every disc and generate an .m3u playlist so your '
              'emulator can swap discs.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: group.members.map((member) {
                final isCurrent = member.slug == entry.slug;
                final label = member.label.isEmpty
                    ? 'Disc ${member.index}'
                    : member.label;

                return ActionChip(
                  avatar: isCurrent
                      ? const Icon(Icons.play_arrow, size: 16)
                      : null,
                  label: Text(label),
                  onPressed: isCurrent
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  EntryDetailScreen(slug: member.slug),
                            ),
                          ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.download),
                label: Text('Download all ${group.members.length} discs'),
                onPressed: () => _downloadAll(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadAll(BuildContext context, WidgetRef ref) async {
    final iaLoggedIn = await ref.read(iaLoggedInProvider.future);
    if (!context.mounted) return;
    final torrentsDisabled = ref.read(settingsProvider).torrentsDisabled;

    final result = await ref.read(downloadProvider.notifier).addDiscGroup(
          group,
          prefs: LinkResolverPrefs(
            isIaLoggedIn: iaLoggedIn,
            torrentsDisabled: torrentsDisabled,
          ),
          sourcePriority: kKnownSourcePriority,
        );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();

    final parts = <String>[];
    if (result.added > 0) parts.add('${result.added} queued');
    if (result.duplicates > 0) parts.add('${result.duplicates} already added');
    if (result.skipped > 0) parts.add('${result.skipped} unavailable');
    final message = parts.isEmpty
        ? 'No discs available to download'
        : 'Discs: ${parts.join(', ')}';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        action: result.added > 0
            ? SnackBarAction(
                label: 'View',
                onPressed: () {
                  ref.read(navigationTabProvider.notifier).state =
                      NavTab.downloads;
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              )
            : null,
      ),
    );
  }
}

class _MetadataCard extends StatefulWidget {
  final GameMetadata metadata;

  const _MetadataCard({required this.metadata});

  @override
  State<_MetadataCard> createState() => _MetadataCardState();
}

class _MetadataCardState extends State<_MetadataCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = widget.metadata.description;
    final hasDescription = description != null && description.isNotEmpty;
    final media = [
      ...widget.metadata.screenshotUrls,
      ...widget.metadata.artworkUrls,
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'About',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (hasDescription) ...[
              const SizedBox(height: 8),
              Text(
                description,
                maxLines: _expanded ? null : 6,
                overflow: _expanded ? null : TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              if (description.length > 300)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? 'Show less' : 'Read more'),
                ),
            ],
            if (media.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: media.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, index) => GestureDetector(
                    onTap: () => _openViewer(context, media, index),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: media[index],
                        height: 150,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: 200,
                          color: theme.colorScheme.surfaceContainerHighest,
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 200,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.broken_image),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openViewer(BuildContext context, List<String> media, int index) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            PageView.builder(
              controller: PageController(initialPage: index),
              itemCount: media.length,
              itemBuilder: (context, page) => InteractiveViewer(
                child: Center(
                  child: CachedNetworkImage(imageUrl: media[page]),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foregroundColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: foregroundColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _RegionChip extends StatelessWidget {
  final String region;
  final Color backgroundColor;
  final Color foregroundColor;

  const _RegionChip({
    required this.region,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            RegionUtils.getFlag(region),
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(width: 6),
          Text(
            region.toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: foregroundColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteButton extends ConsumerWidget {
  final RomEntry entry;
  final bool isCollapsed;
  final bool hasBoxart;

  const _FavoriteButton({
    required this.entry,
    required this.isCollapsed,
    required this.hasBoxart,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFavoriteAsync = ref.watch(isFavoriteProvider(entry.slug));

    return isFavoriteAsync.when(
      loading: () =>
          const IconButton(onPressed: null, icon: Icon(Icons.favorite_border)),
      error: (error, stackTrace) => const SizedBox.shrink(),
      data: (isFavorite) {
        final iconColor = hasBoxart && !isCollapsed ? Colors.white : null;
        return IconButton(
          icon: Icon(
            isFavorite ? Icons.favorite : Icons.favorite_border,
            color: isFavorite ? Colors.red : iconColor,
            shadows: hasBoxart && !isCollapsed
                ? const [
                    Shadow(color: Colors.black, blurRadius: 4),
                    Shadow(color: Colors.black, blurRadius: 8),
                  ]
                : null,
          ),
          onPressed: () async {
            await ref
                .read(favoritesProvider.notifier)
                .toggleFavorite(
                  slug: entry.slug,
                  title: entry.title,
                  platform: entry.platform,
                  boxartUrl: entry.boxartUrl,
                );
            ref.invalidate(isFavoriteProvider(entry.slug));

            if (context.mounted) {
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isFavorite ? 'Removed from wishlist' : 'Added to wishlist',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
          tooltip: isFavorite ? 'Remove from wishlist' : 'Add to wishlist',
        );
      },
    );
  }
}

class _DownloadLinkCard extends ConsumerWidget {
  final RomEntry entry;
  final DownloadLink link;

  const _DownloadLinkCard({required this.entry, required this.link});

  bool get _requiresLogin => link.requiresAuth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggedInAsync = ref.watch(iaLoggedInProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              link.name.isNotEmpty ? link.name : link.filename,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),

            // Source name, file size, file type
            Row(
              children: [
                Icon(
                  Icons.cloud,
                  size: 14,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 4),
                Text(link.host, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(width: 12),
                Icon(
                  Icons.storage,
                  size: 14,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 4),
                Text(
                  link.sizeStr,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.insert_drive_file,
                  size: 14,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 4),
                Text(link.format, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),

            // Badges row
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: link.isTorrent
                        ? Colors.orange.shade700
                        : Colors.green.shade700,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        link.isTorrent ? Icons.hub : Icons.download,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        link.isTorrent ? 'Torrent' : 'Direct',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_requiresLogin)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.shade700,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Login Required',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    link.type,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Download button
            SizedBox(
              width: double.infinity,
              child: _requiresLogin && isLoggedInAsync.valueOrNull != true
                  ? FilledButton.icon(
                      onPressed: () => _startDownload(context, ref),
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Login & Download'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.deepPurple.shade700,
                        foregroundColor: Colors.white,
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: () => _startDownload(context, ref),
                      icon: const Icon(Icons.download),
                      label: const Text('Download'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startDownload(BuildContext context, WidgetRef ref) async {
    final requiresLogin = link.requiresAuth;

    if (requiresLogin) {
      final isLoggedIn = await ref.read(iaLoggedInProvider.future);

      if (!isLoggedIn) {
        if (!context.mounted) return;

        final shouldLogin = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Login Required'),
            content: const Text(
              'This file requires an Internet Archive account to download. '
              'Would you like to log in now?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Log In'),
              ),
            ],
          ),
        );

        if (shouldLogin == true && context.mounted) {
          final loggedIn = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => const InternetArchiveLoginScreen(),
            ),
          );

          // If login was successful, proceed with download
          if (loggedIn == true && context.mounted) {
            ref.invalidate(iaLoggedInProvider);
            _addToDownloadQueue(context, ref);
          }
          return;
        } else {
          return; // User cancelled
        }
      }
    }

    // Proceed with download
    if (!context.mounted) return;

    _addToDownloadQueue(context, ref);
  }

  Future<void> _addToDownloadQueue(BuildContext context, WidgetRef ref) async {
    final (result, existingTask) = await ref
        .read(downloadProvider.notifier)
        .addDownload(
          slug: entry.slug,
          title: entry.title,
          platform: entry.platform,
          boxartUrl: entry.boxartUrl,
          link: link,
        );

    if (!context.mounted) return;

    // Clear any existing snackbar before showing a new one
    ScaffoldMessenger.of(context).clearSnackBars();

    if (result == AddDownloadResult.duplicate) {
      // Show duplicate message with status
      final statusMsg = switch (existingTask.status) {
        DownloadStatus.completed => 'already downloaded',
        DownloadStatus.downloading ||
        DownloadStatus.extracting => 'currently downloading',
        DownloadStatus.pending => 'already in queue',
        DownloadStatus.paused => 'paused in queue',
        DownloadStatus.failed => 'in queue', // shouldn't happen
      };

      final targetTab = existingTask.status == DownloadStatus.completed
          ? NavTab.library
          : NavTab.downloads;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${entry.title}" is $statusMsg'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'View',
            onPressed: () {
              ref.read(navigationTabProvider.notifier).state = targetTab;
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added "${entry.title}" to download queue'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'View',
            onPressed: () {
              // Navigate to downloads tab
              ref.read(navigationTabProvider.notifier).state = NavTab.downloads;
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ),
      );
    }
  }
}

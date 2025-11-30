import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../utils/utils.dart';
import '../widgets/widgets.dart';
import 'entry_detail_screen.dart';

// Provider for view mode preference
final isGridViewProvider = StateProvider<bool>((ref) => false);

class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Set up infinite scroll listener
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _loadMore() {
    final searchState = ref.read(searchProvider);
    if (!searchState.isLoading &&
        searchState.result != null &&
        searchState.result!.hasMore) {
      ref.read(searchProvider.notifier).loadNextPage();
    }
  }

  void _onSearch() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      // Reset to initial state if query is empty
      ref.read(searchProvider.notifier).reset();
    } else {
      ref.read(searchProvider.notifier).search(query: query);
    }
  }

  Future<void> _navigateToRandomEntry() async {
    try {
      final api = ref.read(crocDbApiProvider);
      final randomEntry = await api.getRandomEntry();
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EntryDetailScreen(slug: randomEntry.slug),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final message = ErrorUtils.getUserFriendlyMessage(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _navigateToRandomEntry,
            ),
          ),
        );
      }
    }
  }

  void _showFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const FilterBottomSheet(),
    );
  }

  Widget _buildLandscapeAppBar(SearchState searchState, bool isGridView, int activeFilterCount) {
    return SliverAppBar(
      floating: true,
      snap: true,
      toolbarHeight: 72,
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search ROMs...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            ref.read(searchProvider.notifier).reset();
                            setState(() {});
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => _onSearch(),
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
              ),
            ),
            const SizedBox(width: 4),
            Badge(
              isLabelVisible: activeFilterCount > 0,
              label: Text('$activeFilterCount'),
              child: IconButton(
                icon: const Icon(Icons.filter_list),
                onPressed: _showFilters,
                tooltip: 'Filters',
              ),
            ),
            IconButton(
              icon: const Icon(Icons.shuffle),
              onPressed: () => _navigateToRandomEntry(),
              tooltip: "I'm Feeling Lucky",
            ),
            IconButton(
              icon: Icon(isGridView ? Icons.view_list : Icons.grid_view),
              onPressed: () {
                ref.read(isGridViewProvider.notifier).state = !isGridView;
              },
              tooltip: isGridView ? 'List view' : 'Grid view',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortraitAppBar(SearchState searchState, bool isGridView, int activeFilterCount) {
    return SliverAppBar(
      floating: true,
      snap: true,
      toolbarHeight: 130,
      titleSpacing: 0,
      flexibleSpace: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            children: [
              // Search bar row
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search ROMs...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            ref.read(searchProvider.notifier).reset();
                            setState(() {});
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                onSubmitted: (_) => _onSearch(),
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
              ),
              const SizedBox(height: 12),
              // Action buttons row
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _showFilters,
                      icon: Badge(
                        isLabelVisible: activeFilterCount > 0,
                        label: Text('$activeFilterCount'),
                        child: const Icon(Icons.filter_list),
                      ),
                      label: const Text('Filters'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _navigateToRandomEntry(),
                      icon: const Icon(Icons.shuffle),
                      label: const Text('Random'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    icon: Icon(isGridView ? Icons.view_list : Icons.grid_view),
                    onPressed: () {
                      ref.read(isGridViewProvider.notifier).state = !isGridView;
                    },
                    tooltip: isGridView ? 'List view' : 'Grid view',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final isGridView = ref.watch(isGridViewProvider);
    final activeFilterCount = searchState.selectedPlatforms.length +
        searchState.selectedRegions.length;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          // Only refresh if a search has already been performed
          if (searchState.result != null) {
            await ref.read(searchProvider.notifier).search();
          }
        },
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // Search bar - compact in landscape, spacious in portrait
            if (isLandscape)
              _buildLandscapeAppBar(searchState, isGridView, activeFilterCount)
            else
              _buildPortraitAppBar(searchState, isGridView, activeFilterCount),

            // Active filter chips
            if (activeFilterCount > 0)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      ...searchState.selectedPlatforms.map((p) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Chip(
                              label: Text(PlatformNames.getDisplayName(p)),
                              onDeleted: () {
                                final updated = searchState.selectedPlatforms
                                    .where((id) => id != p)
                                    .toList();
                                ref.read(searchProvider.notifier)
                                  ..setSelectedPlatforms(updated)
                                  ..search();
                              },
                              visualDensity: VisualDensity.compact,
                            ),
                          )),
                      ...searchState.selectedRegions.map((r) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Chip(
                              label: Text(RegionUtils.getFlagWithCode(r)),
                              onDeleted: () {
                                final updated = searchState.selectedRegions
                                    .where((id) => id != r)
                                    .toList();
                                ref.read(searchProvider.notifier)
                                  ..setSelectedRegions(updated)
                                  ..search();
                              },
                              visualDensity: VisualDensity.compact,
                            ),
                          )),
                    ],
                  ),
                ),
              ),

            // Results count
            if (searchState.result != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                  child: Text(
                    '${searchState.result!.totalResults} results',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),

            // Results
            _buildSliverResults(searchState, isGridView),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverResults(SearchState searchState, bool isGridView) {
    if (searchState.isLoading && searchState.result == null) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (searchState.error != null) {
      return SliverErrorView(
        error: searchState.error,
        onRetry: _onSearch,
      );
    }

    // Show initial state before any search is performed
    if (searchState.result == null) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'Search for ROMs',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter a game name or use filters to browse',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[500],
                    ),
              ),
            ],
          ),
        ),
      );
    }

    final entries = searchState.result?.entries ?? [];

    if (entries.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.search_off, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('No results found'),
              if (searchState.selectedPlatforms.isNotEmpty ||
                  searchState.selectedRegions.isNotEmpty) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    ref.read(searchProvider.notifier)
                      ..clearFilters()
                      ..search();
                  },
                  child: const Text('Clear filters'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return isGridView
        ? _buildSliverGrid(entries, searchState)
        : _buildSliverList(entries, searchState);
  }

  Widget _buildSliverList(List entries, SearchState searchState) {
    final downloadedSlugs = ref.watch(downloadedSlugsProvider);
    final downloadedSet = downloadedSlugs.valueOrNull ?? <String>{};

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index >= entries.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            );
          }

          final entry = entries[index];
          return Column(
            children: [
              RomListTile(
                entry: entry,
                isDownloaded: downloadedSet.contains(entry.slug),
                onTap: () => _openEntry(entry.slug),
              ),
              if (index < entries.length - 1) const Divider(height: 1),
            ],
          );
        },
        childCount: entries.length + (searchState.result!.hasMore ? 1 : 0),
      ),
    );
  }

  Widget _buildSliverGrid(List entries, SearchState searchState) {
    final downloadedSlugs = ref.watch(downloadedSlugsProvider);
    final downloadedSet = downloadedSlugs.valueOrNull ?? <String>{};

    // Get screen width to calculate columns
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 600
        ? (screenWidth > 900 ? 5 : 4)
        : (screenWidth > 400 ? 3 : 2);

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.7,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index >= entries.length) {
              return const Center(child: CircularProgressIndicator());
            }

            final entry = entries[index];
            return RomGridCard(
              entry: entry,
              isDownloaded: downloadedSet.contains(entry.slug),
              onTap: () => _openEntry(entry.slug),
            );
          },
          childCount: entries.length + (searchState.result!.hasMore ? 1 : 0),
        ),
      ),
    );
  }

  void _openEntry(String slug) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EntryDetailScreen(slug: slug),
      ),
    );
  }
}

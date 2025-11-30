import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/library_provider.dart';
import '../utils/utils.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final libraryState = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search library...',
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  ref.read(libraryProvider.notifier).setSearchQuery(value);
                },
              )
            : const Text('Library'),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchController.clear();
                  ref.read(libraryProvider.notifier).setSearchQuery('');
                }
              });
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'verify') {
                await ref.read(libraryProvider.notifier).verifyFiles();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Files verified')),
                  );
                }
              } else if (value == 'cleanup') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clean Up Library'),
                    content: const Text(
                      'Remove entries for files that no longer exist on disk?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Clean Up'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await ref
                      .read(libraryProvider.notifier)
                      .cleanupMissingFiles();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Library cleaned up')),
                    );
                  }
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'verify',
                child: ListTile(
                  leading: Icon(Icons.verified),
                  title: Text('Verify Files'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'cleanup',
                child: ListTile(
                  leading: Icon(Icons.cleaning_services),
                  title: Text('Clean Up'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Platform filter chips
          if (libraryState.platforms.isNotEmpty)
            Container(
              height: 50,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: libraryState.selectedPlatform == null,
                    onSelected: (_) {
                      ref
                          .read(libraryProvider.notifier)
                          .setSelectedPlatform(null);
                    },
                  ),
                  const SizedBox(width: 8),
                  ...libraryState.platforms.map((platform) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(PlatformNames.getDisplayName(platform)),
                        selected: libraryState.selectedPlatform == platform,
                        onSelected: (_) {
                          ref
                              .read(libraryProvider.notifier)
                              .setSelectedPlatform(
                                libraryState.selectedPlatform == platform
                                    ? null
                                    : platform,
                              );
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),

          // Library items
          Expanded(
            child: libraryState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : libraryState.filteredItems.isEmpty
                ? _buildEmptyState(libraryState)
                : RefreshIndicator(
                    onRefresh: () =>
                        ref.read(libraryProvider.notifier).refresh(),
                    child: ListView.builder(
                      itemCount: libraryState.filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = libraryState.filteredItems[index];
                        final fileExists = libraryState.fileExists(
                          item.filePath,
                        );
                        return _LibraryItemTile(
                          item: item,
                          fileExists: fileExists,
                          onTap: () => _openFile(item),
                          onDelete: () => _confirmDelete(item),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(LibraryState state) {
    if (state.searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No results for "${state.searchQuery}"',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    if (state.selectedPlatform != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No ${PlatformNames.getDisplayName(state.selectedPlatform!)} ROMs',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_books, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Your library is empty',
            style: TextStyle(color: Colors.grey[600], fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Downloaded ROMs will appear here',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Future<void> _openFile(DownloadTask item) async {
    if (item.filePath == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('File path not found')));
      return;
    }

    final file = File(item.filePath!);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('File no longer exists')));
      }
      return;
    }

    // Show file info dialog
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(item.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('Platform', PlatformNames.getDisplayName(item.platform)),
              _infoRow('Format', item.link.format.toUpperCase()),
              _infoRow('Size', item.link.sizeStr),
              const SizedBox(height: 8),
              Text(
                'Path:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.filePath!,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          Text(value),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(DownloadTask item) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete ROM'),
        content: Text('Delete "${item.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'remove'),
            child: const Text('Remove from Library'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete File'),
          ),
        ],
      ),
    );

    if (result == 'remove') {
      await ref
          .read(libraryProvider.notifier)
          .deleteItem(item, deleteFile: false);
      // Invalidate download status providers so search results update
      ref.invalidate(downloadedSlugsProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Removed from library')));
      }
    } else if (result == 'delete') {
      await ref
          .read(libraryProvider.notifier)
          .deleteItem(item, deleteFile: true);
      // Invalidate download status providers so search results update
      ref.invalidate(downloadedSlugsProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ROM deleted')));
      }
    }
  }
}

class _LibraryItemTile extends StatelessWidget {
  final DownloadTask item;
  final bool fileExists;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _LibraryItemTile({
    required this.item,
    required this.fileExists,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 56,
          height: 56,
          child: item.boxartUrl != null
              ? CachedNetworkImage(
                  imageUrl: item.boxartUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    color: Colors.grey[300],
                    child: const Icon(Icons.gamepad, color: Colors.grey),
                  ),
                  errorWidget: (_, _, _) => Container(
                    color: Colors.grey[300],
                    child: const Icon(Icons.gamepad, color: Colors.grey),
                  ),
                )
              : Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.gamepad, color: Colors.grey),
                ),
        ),
      ),
      title: Text(
        item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: fileExists ? null : Colors.grey,
          decoration: fileExists ? null : TextDecoration.lineThrough,
        ),
      ),
      subtitle: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              PlatformNames.getDisplayName(item.platform),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            item.link.format.toUpperCase(),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(width: 8),
          Text(
            item.link.sizeStr,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          if (!fileExists) ...[
            const SizedBox(width: 8),
            Icon(Icons.warning, size: 14, color: Colors.orange[700]),
            const SizedBox(width: 4),
            Text(
              'Missing',
              style: TextStyle(fontSize: 12, color: Colors.orange[700]),
            ),
          ],
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
      onTap: onTap,
    );
  }
}

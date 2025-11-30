import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../utils/utils.dart';

class RomListTile extends StatelessWidget {
  final RomEntry entry;
  final VoidCallback? onTap;
  final bool isDownloaded;

  const RomListTile({
    super.key,
    required this.entry,
    this.onTap,
    this.isDownloaded = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Stack(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: entry.boxartUrl != null
                ? CachedNetworkImage(
                    imageUrl: entry.boxartUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    errorWidget: (context, url, error) =>
                        const Icon(Icons.videogame_asset, size: 32),
                  )
                : const Icon(Icons.videogame_asset, size: 32),
          ),
          if (isDownloaded)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.check, size: 12, color: Colors.white),
              ),
            ),
        ],
      ),
      title: Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          _PlatformChip(platform: entry.platform),
          const SizedBox(width: 4),
          if (isDownloaded) ...[
            const _DownloadedBadge(),
            const SizedBox(width: 4),
          ],
          if (entry.regions.isNotEmpty)
            Text(
              RegionUtils.getFlags(entry.regions),
              style: const TextStyle(fontSize: 14),
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _PlatformChip extends StatelessWidget {
  final String platform;

  const _PlatformChip({required this.platform});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        PlatformNames.getDisplayName(platform),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _DownloadedBadge extends StatelessWidget {
  const _DownloadedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.green.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.download_done, size: 10, color: Colors.green.shade700),
          const SizedBox(width: 2),
          Text(
            'Downloaded',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';

class FilterBottomSheet extends ConsumerStatefulWidget {
  const FilterBottomSheet({super.key});

  @override
  ConsumerState<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends ConsumerState<FilterBottomSheet> {
  late Set<String> _selectedPlatforms;
  late Set<String> _selectedRegions;

  @override
  void initState() {
    super.initState();
    final searchState = ref.read(searchProvider);
    _selectedPlatforms = searchState.selectedPlatforms.toSet();
    _selectedRegions = searchState.selectedRegions.toSet();
  }

  @override
  Widget build(BuildContext context) {
    final platformsAsync = ref.watch(platformsProvider);
    final regionsAsync = ref.watch(regionsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Filters',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _selectedPlatforms.clear();
                          _selectedRegions.clear();
                        });
                      },
                      child: const Text('Clear all'),
                    ),
                  ],
                ),
              ),

              const Divider(),

              // Filter content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Regions section
                    Text(
                      'Regions',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    regionsAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Text('Error loading regions: $e'),
                      data: (regions) => Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: regions.map((region) {
                          final isSelected = _selectedRegions.contains(
                            region.id,
                          );
                          return FilterChip(
                            label: Text(region.name),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedRegions.add(region.id);
                                } else {
                                  _selectedRegions.remove(region.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Platforms section
                    Text(
                      'Platforms',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    platformsAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Text('Error loading platforms: $e'),
                      data: (platforms) => _buildPlatformsList(platforms),
                    ),
                  ],
                ),
              ),

              // Apply button
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        ref.read(searchProvider.notifier)
                          ..setSelectedPlatforms(_selectedPlatforms.toList())
                          ..setSelectedRegions(_selectedRegions.toList())
                          ..search();
                        Navigator.pop(context);
                      },
                      child: const Text('Apply Filters'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlatformsList(List<Platform> platforms) {
    // Group platforms by brand
    final grouped = <String, List<Platform>>{};
    for (final platform in platforms) {
      grouped.putIfAbsent(platform.brand, () => []).add(platform);
    }

    // Sort brands alphabetically
    final sortedBrands = grouped.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sortedBrands.map((brand) {
        final brandPlatforms = grouped[brand]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Text(
                brand,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: brandPlatforms.map((platform) {
                final isSelected = _selectedPlatforms.contains(platform.id);
                return FilterChip(
                  label: Text(platform.name),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedPlatforms.add(platform.id);
                      } else {
                        _selectedPlatforms.remove(platform.id);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
        );
      }).toList(),
    );
  }
}

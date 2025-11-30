import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/crocdb_api.dart';
import '../models/models.dart';
import 'api_provider.dart';

class SearchState {
  final String query;
  final List<String> selectedPlatforms;
  final List<String> selectedRegions;
  final SearchResult? result;
  final bool isLoading;
  final dynamic error; // Store the actual error object for better error display

  const SearchState({
    this.query = '',
    this.selectedPlatforms = const [],
    this.selectedRegions = const [],
    this.result,
    this.isLoading = false,
    this.error,
  });

  SearchState copyWith({
    String? query,
    List<String>? selectedPlatforms,
    List<String>? selectedRegions,
    SearchResult? result,
    bool? isLoading,
    dynamic error,
    bool clearError = false,
  }) {
    return SearchState(
      query: query ?? this.query,
      selectedPlatforms: selectedPlatforms ?? this.selectedPlatforms,
      selectedRegions: selectedRegions ?? this.selectedRegions,
      result: result ?? this.result,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class SearchNotifier extends StateNotifier<SearchState> {
  final CrocDbApi _api;

  SearchNotifier(this._api) : super(const SearchState());

  Future<void> search({String? query}) async {
    state = state.copyWith(
      query: query ?? state.query,
      isLoading: true,
      clearError: true,
    );

    try {
      final result = await _api.search(
        query: state.query.isEmpty ? null : state.query,
        platforms: state.selectedPlatforms.isEmpty ? null : state.selectedPlatforms,
        regions: state.selectedRegions.isEmpty ? null : state.selectedRegions,
        page: 1,
      );
      state = state.copyWith(result: result, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e, isLoading: false);
    }
  }

  Future<void> loadNextPage() async {
    final currentResult = state.result;
    if (currentResult == null || !currentResult.hasMore || state.isLoading) {
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final nextPage = currentResult.currentPage + 1;
      final result = await _api.search(
        query: state.query.isEmpty ? null : state.query,
        platforms: state.selectedPlatforms.isEmpty ? null : state.selectedPlatforms,
        regions: state.selectedRegions.isEmpty ? null : state.selectedRegions,
        page: nextPage,
      );

      // Append new entries to existing ones
      final combinedEntries = [...currentResult.entries, ...result.entries];
      final combinedResult = SearchResult(
        entries: combinedEntries,
        totalResults: result.totalResults,
        currentPage: result.currentPage,
        totalPages: result.totalPages,
        currentResults: combinedEntries.length,
      );

      state = state.copyWith(result: combinedResult, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e, isLoading: false);
    }
  }

  void setSelectedPlatforms(List<String> platforms) {
    state = state.copyWith(selectedPlatforms: platforms);
  }

  void setSelectedRegions(List<String> regions) {
    state = state.copyWith(selectedRegions: regions);
  }

  void clearFilters() {
    state = state.copyWith(
      selectedPlatforms: [],
      selectedRegions: [],
    );
  }

  /// Reset to initial state (no search performed)
  void reset() {
    state = const SearchState();
  }
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  final api = ref.watch(crocDbApiProvider);
  return SearchNotifier(api);
});

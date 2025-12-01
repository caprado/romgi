import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/update_service.dart';

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService();
});

enum UpdateStatus {
  idle,
  checking,
  available,
  downloading,
  readyToInstall,
  error,
}

class UpdateState {
  final UpdateStatus status;
  final AppRelease? availableUpdate;
  final double downloadProgress;
  final String? downloadedApkPath;
  final String? errorMessage;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.availableUpdate,
    this.downloadProgress = 0,
    this.downloadedApkPath,
    this.errorMessage,
  });

  UpdateState copyWith({
    UpdateStatus? status,
    AppRelease? availableUpdate,
    double? downloadProgress,
    String? downloadedApkPath,
    String? errorMessage,
    bool clearUpdate = false,
    bool clearError = false,
  }) {
    return UpdateState(
      status: status ?? this.status,
      availableUpdate: clearUpdate ? null : (availableUpdate ?? this.availableUpdate),
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadedApkPath: downloadedApkPath ?? this.downloadedApkPath,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class UpdateNotifier extends StateNotifier<UpdateState> {
  final UpdateService _service;
  CancelToken? _downloadCancelToken;

  UpdateNotifier(this._service) : super(const UpdateState());

  Future<void> checkForUpdate() async {
    state = state.copyWith(status: UpdateStatus.checking, clearError: true);

    try {
      final update = await _service.checkForUpdate();
      if (update != null) {
        state = state.copyWith(
          status: UpdateStatus.available,
          availableUpdate: update,
        );
      } else {
        state = state.copyWith(status: UpdateStatus.idle, clearUpdate: true);
      }
    } catch (e) {
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: 'Failed to check for updates',
      );
    }
  }

  Future<void> downloadUpdate() async {
    final update = state.availableUpdate;
    if (update == null || update.apkDownloadUrl == null) return;

    _downloadCancelToken = CancelToken();
    state = state.copyWith(status: UpdateStatus.downloading, downloadProgress: 0);

    try {
      final apkPath = await _service.downloadUpdate(
        update,
        onProgress: (received, total) {
          if (total > 0) {
            state = state.copyWith(downloadProgress: received / total);
          }
        },
        cancelToken: _downloadCancelToken,
      );

      if (apkPath != null) {
        state = state.copyWith(
          status: UpdateStatus.readyToInstall,
          downloadedApkPath: apkPath,
          downloadProgress: 1.0,
        );
      } else {
        state = state.copyWith(
          status: UpdateStatus.error,
          errorMessage: 'Download failed',
        );
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        state = state.copyWith(status: UpdateStatus.available);
      } else {
        state = state.copyWith(
          status: UpdateStatus.error,
          errorMessage: 'Download failed: ${e.message}',
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: 'Download failed',
      );
    } finally {
      _downloadCancelToken = null;
    }
  }

  void cancelDownload() {
    _downloadCancelToken?.cancel();
  }

  Future<bool> installUpdate() async {
    final apkPath = state.downloadedApkPath;
    if (apkPath == null) return false;

    return _service.installApk(apkPath);
  }

  void dismiss() {
    state = state.copyWith(status: UpdateStatus.idle, clearUpdate: true);
  }
}

final updateProvider = StateNotifierProvider<UpdateNotifier, UpdateState>((ref) {
  final service = ref.watch(updateServiceProvider);
  return UpdateNotifier(service);
});

/// Provider for current app version
final currentVersionProvider = FutureProvider<String>((ref) async {
  final service = ref.watch(updateServiceProvider);
  return service.getCurrentVersion();
});

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../torrent/torrent_api.g.dart';
import 'database_service.dart';
import 'host_adapter.dart';
import 'notification_service.dart';
import 'seven_zip_service.dart';
import 'storage_service.dart';
import 'torrent_service.dart';

enum AddDownloadResult { added, duplicate }

class DownloadService {
  final DatabaseService _db;
  final StorageService _storage;
  final NotificationService _notifications;
  final HostAdapterRegistry _adapters;
  final TorrentService _torrents;
  final SevenZipService _sevenZip;
  final Dio _dio;
  Dio? _nativeDio;
  final _uuid = const Uuid();
  final Map<String, StreamSubscription<TorrentProgress>> _torrentProgressSubs = {};
  final Map<String, StreamSubscription<({String infohash, String error})>>
      _torrentErrorSubs = {};

  final _downloadController = StreamController<DownloadTask>.broadcast();
  Stream<DownloadTask> get downloadStream => _downloadController.stream;

  final Map<String, CancelToken> _activeCancelTokens = {};
  final Map<String, DownloadTask> _activeTasks = {};
  final Set<String> _pausedTaskIds = {};
  DateTime? _lastNotificationUpdate;
  bool _isProcessingQueue = false;

  final Map<String, int> _lastBytesReceived = {};
  final Map<String, DateTime> _lastSpeedUpdate = {};
  final Map<String, DateTime> _downloadStartTime = {};
  final Map<String, int> _downloadStartBytes = {};
  final Map<String, DateTime> _lastDbUpdate = {};

  // Max concurrent downloads (0 = unlimited)
  int _maxConcurrentDownloads = 3;

  void setMaxConcurrentDownloads(int value) {
    _maxConcurrentDownloads = value;
    // Try to start more downloads if limit increased
    _processQueue();
  }

  DownloadService({
    required DatabaseService db,
    required StorageService storage,
    required NotificationService notifications,
    required HostAdapterRegistry adapters,
    required TorrentService torrents,
    required SevenZipService sevenZip,
    Dio? dio,
  })  : _db = db,
        _storage = storage,
        _notifications = notifications,
        _adapters = adapters,
        _torrents = torrents,
        _sevenZip = sevenZip,
        _dio = dio ?? Dio();

  Future<void> initialize() async {
    await _notifications.initialize();
    await _notifications.requestPermissions();
    await _initForegroundTask();

    // Resume any downloads that were in progress when the app closed
    await _resumePendingDownloads();
  }

  Future<void> _initForegroundTask() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'download_foreground',
        channelName: 'Download Service',
        channelDescription: 'Keeps downloads running in background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> _startForegroundTask(String title) async {
    if (await FlutterForegroundTask.isRunningService) return;

    // Request battery optimization exemption for reliable background downloads
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    await FlutterForegroundTask.startService(
      notificationTitle: 'Downloading',
      notificationText: title,
    );
  }

  Future<void> _stopForegroundTask() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  Future<void> _updateForegroundTask(String title, String text) async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    }
  }

  Future<void> _resumePendingDownloads() async {
    final downloading = await _db.getDownloadsByStatus(
      DownloadStatus.downloading,
    );

    for (final task in downloading) {
      final updated = task.copyWith(status: DownloadStatus.pending);
      await _db.updateDownload(updated);
    }

    final extracting = await _db.getDownloadsByStatus(
      DownloadStatus.extracting,
    );

    for (final task in extracting) {
      final updated = task.copyWith(status: DownloadStatus.pending);
      await _db.updateDownload(updated);
    }

    _processQueue();
  }

  Future<(AddDownloadResult, DownloadTask)> addDownload({
    required String slug,
    required String title,
    required String platform,
    String? boxartUrl,
    required DownloadLink link,
  }) async {
    final existingDownload = await _db.findExistingDownload(slug);
    if (existingDownload != null) {
      return (AddDownloadResult.duplicate, existingDownload);
    }

    final downloadTask = DownloadTask(
      id: _uuid.v4(),
      slug: slug,
      title: title,
      platform: platform,
      boxartUrl: boxartUrl,
      link: link,
      status: DownloadStatus.pending,
      createdAt: DateTime.now(),
    );

    await _db.insertDownload(downloadTask);
    _downloadController.add(downloadTask);

    _processQueue();

    return (AddDownloadResult.added, downloadTask);
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;

    _isProcessingQueue = true;

    try {
      // Check if we can start more downloads
      final activeCount = _activeTasks.length;
      final canStartMore =
          _maxConcurrentDownloads == 0 || activeCount < _maxConcurrentDownloads;

      if (!canStartMore) return;

      final pending = await _db.getDownloadsByStatus(DownloadStatus.pending);
      if (pending.isEmpty) {
        if (_activeTasks.isEmpty) {
          await _notifications.cancelProgressNotification();
          await _stopForegroundTask();
        }

        return;
      }

      final slotsAvailable = _maxConcurrentDownloads == 0
          ? pending.length
          : _maxConcurrentDownloads - activeCount;

      // Start downloads for available slots (one at a time to maintain accurate count)
      for (var i = 0; i < slotsAvailable && i < pending.length; i++) {
        // Re-check active count to ensure we don't exceed limit
        if (_maxConcurrentDownloads > 0 &&
            _activeTasks.length >= _maxConcurrentDownloads) {
          break;
        }

        final task = pending[i];
        if (!_activeTasks.containsKey(task.id)) {
          // Add to active tasks immediately to prevent race conditions
          _activeTasks[task.id] = task;
          _startDownload(task);
        }
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  static const String authRequiredError = 'LOGIN_REQUIRED';

  static bool isAuthRequiredError(String? error) {
    if (error == null) return false;

    return error == authRequiredError ||
        error.contains('401') ||
        error.contains('Authorization Required') ||
        error.contains('Unauthorized');
  }

  static bool _isMyrientUrl(String url) {
    return url.contains('myrient.erista.me');
  }

  /// Check if a DioException is retryable
  static bool _isRetryableError(DioException e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return true;
    }

    // Check for SSL errors in the error message or inner error
    final errorString = e.error?.toString().toLowerCase() ?? '';
    final messageString = e.message?.toLowerCase() ?? '';
    final combined = '$errorString $messageString';

    if (combined.contains('ssl') ||
        combined.contains('handshake') ||
        combined.contains('certificate') ||
        combined.contains('tls') ||
        combined.contains('connection reset') ||
        combined.contains('connection refused') ||
        combined.contains('err_ssl') ||
        combined.contains('net_error')) {
      return true;
    }

    return false;
  }

  Dio _getNativeDio() {
    if (_nativeDio == null) {
      _nativeDio = Dio();
      _nativeDio!.httpClientAdapter = NativeAdapter();
    }
    return _nativeDio!;
  }

  Future<void> _startDownload(DownloadTask task) async {
    final adapter = _adapters.adapterFor(task.link);

    if (adapter.isTorrent) {
      await _startTorrentDownload(task, adapter);
      return;
    }

    final cancelToken = CancelToken();
    _activeCancelTokens[task.id] = cancelToken;

    if (!await adapter.canStartDownload(task.link)) {
      final failedTask = task.copyWith(
        status: DownloadStatus.failed,
        error: adapter.authError,
      );
      _activeTasks.remove(task.id);
      _activeCancelTokens.remove(task.id);
      await _db.updateDownload(failedTask);
      _downloadController.add(failedTask);
      _processQueue();
      return;
    }

    await _startForegroundTask(task.title);

    var updatedTask = task.copyWith(status: DownloadStatus.downloading);
    _activeTasks[task.id] = updatedTask;
    await _db.updateDownload(updatedTask);
    _downloadController.add(updatedTask);
    await _updateNotifications();

    try {
      final downloadPath = await _storage.getDownloadPath(
        task.platform,
        task.link.filename,
      );

      int downloadedBytes = 0;
      bool attemptResume = false;

      final file = File(downloadPath);
      if (await file.exists()) {
        downloadedBytes = await file.length();
        // Only attempt resume if we have meaningful progress
        attemptResume = downloadedBytes > 0;

        // Validate that partial file isn't larger than expected total
        // If it is, the file is likely corrupt
        if (attemptResume &&
            task.link.size > 0 &&
            downloadedBytes >= task.link.size) {
          await file.delete();
          downloadedBytes = 0;
          attemptResume = false;
        }
      } else {
        // File doesn't exist but task may have stored progress, reset it
        if (task.downloadedBytes > 0 || task.progress > 0) {
          updatedTask = updatedTask.copyWith(progress: 0, downloadedBytes: 0);
        }
      }

      final headers = <String, dynamic>{
        // Browser-like headers to avoid anti-bot detection
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'Accept': '*/*',
        'Accept-Language': 'en-US,en;q=0.9',
        'Connection': 'keep-alive',
      };

      if (attemptResume) {
        headers['Range'] = 'bytes=$downloadedBytes-';
      }

      await adapter.prepareHeaders(headers, task.link);

      // Add Myrient-specific headers to avoid throttling
      if (_isMyrientUrl(task.link.url)) {
        headers['Referer'] = 'https://myrient.erista.me/';
        headers['Origin'] = 'https://myrient.erista.me';
      }

      final isMyrient = _isMyrientUrl(task.link.url);
      final dio = isMyrient ? _getNativeDio() : _dio;

      // If resuming, verify the server actually supports range requests
      // by checking if the response is 206 Partial Content
      int resumeOffset = 0;
      if (attemptResume) {
        try {
          // Make a HEAD request to check Accept-Ranges support
          final headResponse = await dio.head(
            task.link.url,
            options: Options(headers: Map.from(headers)..remove('Range')),
            cancelToken: cancelToken,
          );
          final acceptRanges = headResponse.headers.value('accept-ranges');
          final supportsRange = acceptRanges != null && acceptRanges != 'none';

          if (supportsRange) {
            resumeOffset = downloadedBytes;
            headers['Range'] = 'bytes=$downloadedBytes-';
          } else {
            // Server doesn't support range requests - delete partial and start fresh
            await file.delete();
            downloadedBytes = 0;
          }
        } catch (_) {
          // HEAD request failed - try download anyway, but don't attempt resume
          await file.delete();
          downloadedBytes = 0;
          headers.remove('Range');
        }
      }

      // Retry logic for transient SSL/connection errors
      const maxRetries = 3;
      var retryCount = 0;
      while (true) {
        try {
          // IA redirects downloads to CDN nodes (e.g. dn721009.ca.archive.org).
          // Dio may not forward Cookie headers on cross-host redirects.
          // Resolve the final URL first, then download with headers intact.
          var downloadUrl = task.link.url;
          if (headers.containsKey('Cookie')) {
            try {
              final headResp = await dio.head(
                task.link.url,
                cancelToken: cancelToken,
                options: Options(
                  headers: headers,
                  followRedirects: true,
                  validateStatus: (s) => s != null && s < 500,
                ),
              );
              if (headResp.realUri.toString() != task.link.url) {
                downloadUrl = headResp.realUri.toString();
              }
            } catch (_) {
              // Fall through to direct download
            }
          }

          await dio.download(
            downloadUrl,
            downloadPath,
            cancelToken: cancelToken,
            deleteOnError: false,
            options: Options(headers: headers),
            onReceiveProgress: (received, total) async {
              if (_pausedTaskIds.contains(task.id)) return;

              final actualReceived = resumeOffset + received;
              final actualTotal =
                  total > 0 ? resumeOffset + total : task.link.size;
              final progress =
                  actualTotal > 0 ? actualReceived / actualTotal : 0.0;

              int? newBytesPerSecond;
              final now = DateTime.now();

              // Initialize tracking on first callback
              if (_downloadStartTime[task.id] == null) {
                _downloadStartTime[task.id] = now;
                _downloadStartBytes[task.id] = actualReceived;
                _lastSpeedUpdate[task.id] = now;
                _lastBytesReceived[task.id] = actualReceived;
              } else {
                final lastUpdate = _lastSpeedUpdate[task.id]!;
                final elapsed = now.difference(lastUpdate).inMilliseconds;

                if (elapsed >= 500) {
                  // Calculate average speed over entire download for accuracy
                  final totalElapsed = now
                      .difference(_downloadStartTime[task.id]!)
                      .inMilliseconds;
                  final totalBytesDownloaded =
                      actualReceived - _downloadStartBytes[task.id]!;

                  if (totalElapsed > 0 && totalBytesDownloaded > 0) {
                    newBytesPerSecond =
                        (totalBytesDownloaded * 1000 / totalElapsed).round();
                  }

                  _lastSpeedUpdate[task.id] = now;
                  _lastBytesReceived[task.id] = actualReceived;
                }
              }

              updatedTask = updatedTask.copyWith(
                progress: progress,
                downloadedBytes: actualReceived,
                totalBytes: actualTotal,
                bytesPerSecond: newBytesPerSecond ?? updatedTask.bytesPerSecond,
              );
              _activeTasks[task.id] = updatedTask;
              _downloadController.add(updatedTask);

              final lastDbUpdate = _lastDbUpdate[task.id];
              if (lastDbUpdate == null ||
                  now.difference(lastDbUpdate).inMilliseconds > 2000) {
                _lastDbUpdate[task.id] = now;
                // Use unawaited to prevent blocking the progress callback
                _db.updateDownload(updatedTask);
              }

              // Throttle notification updates to every 500ms
              if (_lastNotificationUpdate == null ||
                  now.difference(_lastNotificationUpdate!).inMilliseconds >
                      500) {
                _lastNotificationUpdate = now;
                _updateNotifications();
              }
            },
          );
          break;
        } on DioException catch (e) {
          final isRetryable = _isRetryableError(e);
          retryCount++;

          if (!isRetryable || retryCount >= maxRetries) {
            rethrow; // Not retryable or max retries reached
          }

          // Wait before retrying (exponential backoff: 1s, 2s, 4s)
          final delay = Duration(seconds: 1 << (retryCount - 1));
          await Future.delayed(delay);
        }
      }

      if (_shouldExtract(task.link.filename)) {
        updatedTask = updatedTask.copyWith(status: DownloadStatus.extracting);
        _activeTasks[task.id] = updatedTask;
        await _db.updateDownload(updatedTask);
        _downloadController.add(updatedTask);
        await _updateNotifications();

        try {
          final extractedPath = await _extractArchive(downloadPath, task.platform);
          // Only delete archive after successful extraction
          await File(downloadPath).delete();
          updatedTask = updatedTask.copyWith(
            status: DownloadStatus.completed,
            progress: 1.0,
            filePath: extractedPath,
            completedAt: DateTime.now(),
          );
        } catch (_) {
          // Extraction failed - keep the downloaded file as-is
          updatedTask = updatedTask.copyWith(
            status: DownloadStatus.completed,
            progress: 1.0,
            filePath: downloadPath,
            completedAt: DateTime.now(),
          );
        }
      } else {
        updatedTask = updatedTask.copyWith(
          status: DownloadStatus.completed,
          progress: 1.0,
          filePath: downloadPath,
          completedAt: DateTime.now(),
        );
      }
      await _db.updateDownload(updatedTask);
      _downloadController.add(updatedTask);
      await _notifications.updateForTask(updatedTask);
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) {
        // Download was paused/cancelled
        if (_pausedTaskIds.contains(task.id)) {
          updatedTask = updatedTask.copyWith(status: DownloadStatus.paused);
          _pausedTaskIds.remove(task.id);
        }
      } else {
        final statusCode = error.response?.statusCode;

        // Handle 416 Range Not Satisfiable - delete partial file and mark for retry
        if (statusCode == 416) {
          // Delete the partial file so next attempt starts fresh
          try {
            final downloadPath = await _storage.getDownloadPath(
              task.platform,
              task.link.filename,
            );
            final file = File(downloadPath);
            if (await file.exists()) {
              await file.delete();
            }
          } catch (_) {
            // Best-effort cleanup — the user can retry either way.
          }

          // Set back to pending so it will be retried automatically
          updatedTask = updatedTask.copyWith(
            status: DownloadStatus.pending,
            progress: 0,
            downloadedBytes: 0,
          );
          await _db.updateDownload(updatedTask);
          _downloadController.add(updatedTask);
          // Don't go to finally cleanup yet - let _processQueue restart this
          _activeTasks.remove(task.id);
          _activeCancelTokens.remove(task.id);
          _lastSpeedUpdate.remove(task.id);
          _lastBytesReceived.remove(task.id);
          _downloadStartTime.remove(task.id);
          _downloadStartBytes.remove(task.id);
          _lastDbUpdate.remove(task.id);
          _processQueue();
          return;
        }

        final isAuthError = statusCode == 401 || statusCode == 403;
        if (isAuthError) {
          await adapter.onAuthFailure(task.link);
        }

        updatedTask = updatedTask.copyWith(
          status: DownloadStatus.failed,
          error: isAuthError
              ? authRequiredError
              : (error.message ?? 'Download failed'),
        );
        await _notifications.updateForTask(updatedTask);
      }
      await _db.updateDownload(updatedTask);
      _downloadController.add(updatedTask);
    } on RangeError {
      // Handle RangeError
      // Delete partial file and mark for retry
      try {
        final downloadPath = await _storage.getDownloadPath(
          task.platform,
          task.link.filename,
        );
        final file = File(downloadPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (error) {
        // Ignore file deletion errors
      }

      updatedTask = updatedTask.copyWith(
        status: DownloadStatus.pending,
        progress: 0,
        downloadedBytes: 0,
      );
      await _db.updateDownload(updatedTask);
      _downloadController.add(updatedTask);
      _activeTasks.remove(task.id);
      _activeCancelTokens.remove(task.id);
      _lastSpeedUpdate.remove(task.id);
      _lastBytesReceived.remove(task.id);
      _downloadStartTime.remove(task.id);
      _downloadStartBytes.remove(task.id);
      _lastDbUpdate.remove(task.id);
      _processQueue();
      return;
    } catch (error, _) {
      updatedTask = updatedTask.copyWith(
        status: DownloadStatus.failed,
        error: error.toString(),
      );
      await _db.updateDownload(updatedTask);
      _downloadController.add(updatedTask);
      await _notifications.updateForTask(updatedTask);
    } finally {
      _activeTasks.remove(task.id);
      _activeCancelTokens.remove(task.id);
      _lastSpeedUpdate.remove(task.id);
      _lastBytesReceived.remove(task.id);
      _downloadStartTime.remove(task.id);
      _downloadStartBytes.remove(task.id);
      _lastDbUpdate.remove(task.id);

      // Stop foreground task if no more active downloads
      if (_activeTasks.isEmpty) {
        await _stopForegroundTask();
      }

      _processQueue();
    }
  }

  Future<void> _startTorrentDownload(
    DownloadTask task,
    HostAdapter adapter,
  ) async {
    final infohash = task.link.torrentInfohash;
    final fileIndex = task.link.torrentFileIndex;
    if (infohash == null || fileIndex == null) {
      final failed = task.copyWith(
        status: DownloadStatus.failed,
        error: 'Torrent metadata missing on link',
      );
      _activeTasks.remove(task.id);
      await _db.updateDownload(failed);
      _downloadController.add(failed);
      _processQueue();
      return;
    }

    // If the destination file (or its extracted form) already exists
    // (e.g. previous session completed but the task was re-queued after
    // a hot restart), skip the torrent and go straight to completion.
    final destPath = await _storage.getDownloadPath(
        task.platform, task.link.filename);
    final destFile = File(destPath);
    var existingPath = destPath;
    var alreadyComplete = false;

    if (await destFile.exists()) {
      final fileSize = await destFile.length();
      if (fileSize > 0 && (task.link.size == 0 || fileSize == task.link.size)) {
        alreadyComplete = true;
      }
    }

    // Also check for an already-extracted file (archive was deleted after
    // extraction in a previous session).
    if (!alreadyComplete && _shouldExtract(task.link.filename)) {
      final platformDir = await _storage.getPlatformDirectory(task.platform);
      final baseName = task.link.filename
          .replaceAll(RegExp(r'\.(zip|7z)$', caseSensitive: false), '');
      try {
        await for (final entity in platformDir.list()) {
          if (entity is File) {
            final name = p.basenameWithoutExtension(entity.path);
            if (name == baseName) {
              existingPath = entity.path;
              alreadyComplete = true;
              break;
            }
          }
        }
      } catch (_) {}
    }

    if (alreadyComplete) {
      var finalPath = existingPath;
      if (existingPath == destPath && _shouldExtract(task.link.filename)) {
        try {
          finalPath = await _extractArchive(destPath, task.platform);
          await File(destPath).delete();
        } catch (_) {}
      }
      final completed = task.copyWith(
        status: DownloadStatus.completed,
        progress: 1.0,
        filePath: finalPath,
        completedAt: DateTime.now(),
      );
      _activeTasks.remove(task.id);
      await _db.updateDownload(completed);
      _downloadController.add(completed);
      _processQueue();
      return;
    }

    await _startForegroundTask(task.title);
    var current = task.copyWith(status: DownloadStatus.downloading);
    _activeTasks[task.id] = current;
    await _db.updateDownload(current);
    _downloadController.add(current);
    await _updateNotifications();

    try {
      // Seeding is intentionally never enabled: when a torrent finishes,
      // it's paused and no upload occurs. The Pigeon API still has a
      // seedingEnabled field, but we always pass false.
      await _torrents.start(seedingEnabled: false);
      // Prefer the real .torrent file when we can derive its URL —
      // this gives libtorrent the webseeds (HTTPS fallback peers) that
      // a bare magnet URI strips out. Critical for archive.org content
      // where the swarm is often dead and HTTPS is the actual reliable
      // path.
      final torrentBytes = await _tryFetchTorrentFile(task.link);
      if (torrentBytes != null) {
        await _torrents.addTorrent(
          torrentBytes: torrentBytes,
          fileIndices: [fileIndex],
        );
      } else {
        final magnet = _buildMagnetUri(infohash);
        await _torrents.addTorrent(
          magnet: magnet,
          fileIndices: [fileIndex],
        );
      }
    } catch (e) {
      final failed = current.copyWith(
        status: DownloadStatus.failed,
        error: 'Torrent failed to start: $e',
      );
      _activeTasks.remove(task.id);
      await _db.updateDownload(failed);
      _downloadController.add(failed);
      _processQueue();
      return;
    }

    _torrentProgressSubs[task.id]?.cancel();
    _torrentProgressSubs[task.id] = _torrents.progressStream
        .where((p) => p.infohash == infohash)
        .listen((p) async {
      // Ignore ticks after we've started finishing this task.
      if (!_activeTasks.containsKey(task.id)) return;

      // Until metadata arrives, p.files is empty. We still want the UI
      // to show "Fetching metadata", peer/seed counts, and the wire
      // download rate so the user sees the torrent is alive.
      final hasMetadata = p.files.length > fileIndex;
      final TorrentFile? file = hasMetadata ? p.files[fileIndex] : null;
      final isComplete = file != null && file.length > 0 &&
          file.bytesDownloaded >= file.length;
      final progress = (file != null && file.length > 0)
          ? (file.bytesDownloaded / file.length).clamp(0.0, 1.0)
          : 0.0;
      current = current.copyWith(
        downloadedBytes: file?.bytesDownloaded ?? 0,
        totalBytes: file?.length ?? 0,
        progress: progress,
        bytesPerSecond: isComplete ? 0 : p.downloadRate,
        peers: p.peers,
        seeds: p.seeds,
        fetchingMetadata: !hasMetadata,
      );
      _activeTasks[task.id] = current;
      _downloadController.add(current);

      // Throttle DB writes the same way the HTTP path does.
      final now = DateTime.now();
      final last = _lastDbUpdate[task.id];
      if (last == null ||
          now.difference(last) >= const Duration(milliseconds: 500)) {
        _lastDbUpdate[task.id] = now;
        await _db.updateDownload(current);
        await _updateNotifications();
      }

      if (isComplete) {
        _activeTasks.remove(task.id);
        await _finishTorrentTask(task, file);
      }
    });

    _torrentErrorSubs[task.id]?.cancel();
    _torrentErrorSubs[task.id] =
        _torrents.errorStream.where((e) => e.infohash == infohash).listen((e) {
      _failTorrentTask(task, e.error, adapter);
    });
  }

  Future<void> _finishTorrentTask(DownloadTask task, TorrentFile file) async {
    final torrentSavePath = await _torrentSavePath();
    if (torrentSavePath == null) return;
    final source = File(p.join(torrentSavePath, file.path));
    if (!await source.exists()) return;

    final dest = await _storage.getDownloadPath(task.platform, task.link.filename);
    try {
      final destFile = File(dest);
      if (await destFile.exists()) await destFile.delete();
      await source.copy(dest);
    } catch (_) {
      // Leaving the file in the torrent dir is recoverable; the user
      // can re-add the same task and we'll skip re-downloading thanks
      // to libtorrent's resume data.
      return;
    }

    var finalPath = dest;

    if (_shouldExtract(task.link.filename)) {
      final extracting = task.copyWith(status: DownloadStatus.extracting);
      _downloadController.add(extracting);
      await _db.updateDownload(extracting);

      try {
        finalPath = await _extractArchive(dest, task.platform);
        await File(dest).delete();
      } catch (_) {
        // Extraction failed — keep the downloaded file as-is.
      }
    }

    final completed = task.copyWith(
      status: DownloadStatus.completed,
      progress: 1.0,
      downloadedBytes: file.length,
      totalBytes: file.length,
      filePath: finalPath,
      completedAt: DateTime.now(),
    );
    await _torrentProgressSubs.remove(task.id)?.cancel();
    await _torrentErrorSubs.remove(task.id)?.cancel();
    // Remove the torrent from libtorrent and clean up the source file
    // in the torrent save directory — the ROM has been copied (and
    // extracted if needed) to its final location, so the torrent data
    // is no longer needed.
    final infohash = task.link.torrentInfohash;
    if (infohash != null) {
      try {
        await _torrents.cancel(infohash);
      } catch (_) {
        // Best-effort; the runtime may already have removed it.
      }
    }
    try {
      if (await source.exists()) await source.delete();
      // Also clean up empty parent directories left behind.
      var parent = source.parent;
      final saveDir = Directory(torrentSavePath);
      while (parent.path != saveDir.path) {
        if (await parent.list().isEmpty) {
          await parent.delete();
          parent = parent.parent;
        } else {
          break;
        }
      }
    } catch (_) {
      // Best-effort cleanup.
    }
    await _db.updateDownload(completed);
    _downloadController.add(completed);
    await _updateNotifications();
    _processQueue();
  }

  void _failTorrentTask(DownloadTask task, String error, HostAdapter adapter) {
    final failed = task.copyWith(status: DownloadStatus.failed, error: error);
    _activeTasks.remove(task.id);
    _torrentProgressSubs.remove(task.id)?.cancel();
    _torrentErrorSubs.remove(task.id)?.cancel();
    _db.updateDownload(failed);
    _downloadController.add(failed);
    adapter.onAuthFailure(task.link);
    _processQueue();
  }

  Future<String?> _torrentSavePath() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return p.join(dir.path, 'torrents');
    } catch (_) {
      return null;
    }
  }

  /// Public-tracker list bundled into every magnet URI we hand to
  /// libtorrent. HTTPS trackers come first because some networks (and
  /// most Android emulators behind NAT) block UDP outbound.
  static const _publicTrackers = <String>[
    'https://tracker.gbitt.info:443/announce',
    'https://tracker.nanoha.org:443/announce',
    'https://opentracker.i2p.rocks:443/announce',
    'https://1337.abcvg.info:443/announce',
    'http://tracker.openbittorrent.com:80/announce',
    'http://tracker.opentrackr.org:1337/announce',
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://open.demonii.com:1337/announce',
    'udp://exodus.desync.com:6969/announce',
    'udp://explodie.org:6969/announce',
    'udp://opentracker.io:6969/announce',
    'udp://tracker.torrent.eu.org:451/announce',
    'udp://bt1.archive.org:6969/announce',
    'udp://open.stealth.si:80/announce',
  ];

  String _buildMagnetUri(String infohash) {
    final parts = <String>['xt=urn:btih:$infohash'];
    for (final t in _publicTrackers) {
      parts.add('tr=${Uri.encodeQueryComponent(t)}');
    }
    return 'magnet:?${parts.join('&')}';
  }

  /// archive.org download URL → identifier (the bit between
  /// `/download/` and the next slash).
  static final _archiveOrgIdRegex =
      RegExp(r'^https?://(?:[a-z0-9.-]+\.)?archive\.org/download/([^/]+)/');

  /// Try to fetch the canonical `.torrent` file for the given link.
  /// Currently only archive.org URLs are supported, since archive.org
  /// publishes a predictable `<id>_archive.torrent` for every item and
  /// it carries webseed URLs that let downloads work even when the
  /// swarm is empty or the UDP tracker is firewalled. Returns null
  /// (and the caller falls back to a magnet) on any failure.
  Future<List<int>?> _tryFetchTorrentFile(DownloadLink link) async {
    final m = _archiveOrgIdRegex.firstMatch(link.url);
    if (m == null) return null;
    final id = m.group(1);
    if (id == null || id.isEmpty) return null;
    final torrentUrl = 'https://archive.org/download/$id/${id}_archive.torrent';
    try {
      final response = await _dio.get<List<int>>(
        torrentUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes != null && bytes.isNotEmpty) return bytes;
    } catch (_) {
      // Best-effort — caller falls back to magnet.
    }
    return null;
  }

  Future<void> _stopTorrentSubscription(DownloadTask task) async {
    await _torrentProgressSubs.remove(task.id)?.cancel();
    await _torrentErrorSubs.remove(task.id)?.cancel();
    final infohash = task.link.torrentInfohash;
    if (infohash != null) {
      try {
        await _torrents.cancel(infohash);
      } catch (_) {
        // Best-effort — the runtime may already have removed the torrent.
      }
    }
  }

  Future<void> _updateNotifications() async {
    if (_activeTasks.isEmpty) {
      await _notifications.cancelProgressNotification();
      return;
    }

    // Show progress for first active download
    final activeList = _activeTasks.values.toList();
    if (activeList.length == 1) {
      await _notifications.updateForTask(activeList.first);
      await _updateForegroundTask(
        'Downloading ${activeList.first.title}',
        '${(activeList.first.progress * 100).toStringAsFixed(0)}%',
      );
    } else {
      // Multiple downloads - show count
      final avgProgress =
          activeList.fold<double>(0, (sum, total) => sum + total.progress) /
          activeList.length;
      await _notifications.showDownloadProgress(
        title: '${activeList.length} downloads',
        progress: avgProgress,
        progressText: '${(avgProgress * 100).toStringAsFixed(0)}%',
      );
      await _updateForegroundTask(
        'Downloading ${activeList.length} files',
        '${(avgProgress * 100).toStringAsFixed(0)}%',
      );
    }
  }

  Future<void> pauseDownload(String id) async {
    if (_activeTasks.containsKey(id)) {
      final task = _activeTasks[id]!;
      if (task.link.isTorrent) {
        // Tear the torrent down on the libtorrent side; the .fastresume
        // file persists so resume picks up where we left off.
        await _stopTorrentSubscription(task);
        _activeTasks.remove(id);
        final paused = task.copyWith(status: DownloadStatus.paused);
        await _db.updateDownload(paused);
        _downloadController.add(paused);
        await _updateNotifications();
        _processQueue();
      } else {
        _pausedTaskIds.add(id);
        _activeCancelTokens[id]?.cancel('Paused by user');
      }
    } else {
      // Queued (pending) download — flip status without touching the runtime.
      final task = await _db.getDownload(id);
      if (task != null && task.status == DownloadStatus.pending) {
        final updated = task.copyWith(status: DownloadStatus.paused);
        await _db.updateDownload(updated);
        _downloadController.add(updated);
      }
    }
  }

  Future<void> resumeDownload(String id) async {
    final task = await _db.getDownload(id);
    if (task != null && task.status == DownloadStatus.paused) {
      final updated = task.copyWith(status: DownloadStatus.pending);
      await _db.updateDownload(updated);
      _downloadController.add(updated);
      await _processQueue();
    }
  }

  Future<void> cancelDownload(String id) async {
    final task = _activeTasks[id] ?? await _db.getDownload(id);
    if (task != null && task.link.isTorrent) {
      await _stopTorrentSubscription(task);
    }
    if (_activeTasks.containsKey(id)) {
      _activeCancelTokens[id]?.cancel('Cancelled by user');
    }

    // Remove from active tasks
    _activeTasks.remove(id);
    _activeCancelTokens.remove(id);
    _pausedTaskIds.remove(id);
    _lastSpeedUpdate.remove(id);
    _lastBytesReceived.remove(id);
    _downloadStartTime.remove(id);
    _downloadStartBytes.remove(id);
    _lastDbUpdate.remove(id);

    await _db.deleteDownload(id);

    if (_activeTasks.isEmpty) {
      await _notifications.cancelProgressNotification();
    }

    // Process queue in case there are pending downloads
    _processQueue();
  }

  Future<void> clearCompletedDownloads() async {
    await _db.hideAllCompletedFromHistory();
  }

  Future<void> hideCompletedDownload(String id) async {
    await _db.hideFromHistory(id);
  }

  Future<List<DownloadTask>> getVisibleCompletedDownloads() async {
    return _db.getVisibleCompletedDownloads();
  }

  Future<void> retryDownload(String id) async {
    final task = await _db.getDownload(id);
    if (task != null && task.status == DownloadStatus.failed) {
      // Delete any partial file to start fresh
      try {
        final downloadPath = await _storage.getDownloadPath(
          task.platform,
          task.link.filename,
        );
        final file = File(downloadPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (error) {
        // Ignore errors deleting partial file
      }

      final updated = task.copyWith(
        status: DownloadStatus.pending,
        progress: 0,
        downloadedBytes: 0,
        totalBytes: 0,
        error: null,
      );
      await _db.updateDownload(updated);
      _downloadController.add(updated);
      _processQueue();
    }
  }

  bool _shouldExtract(String filename) {
    final lower = filename.toLowerCase();
    return lower.endsWith('.zip') || lower.endsWith('.7z');
  }

  Future<String> _extractArchive(String archivePath, String platform) async {
    final platformDir = await _storage.getPlatformDirectory(platform);
    return _sevenZip.extract(archivePath, platformDir.path);
  }

  Future<List<DownloadTask>> getAllDownloads() => _db.getAllDownloads();

  Future<List<DownloadTask>> getActiveDownloads() => _db.getActiveDownloads();

  Future<List<DownloadTask>> getCompletedDownloads() =>
      _db.getCompletedDownloads();

  Future<List<DownloadTask>> getFailedDownloads() =>
      _db.getDownloadsByStatus(DownloadStatus.failed);

  Future<bool> isDownloaded(String slug) => _db.isSlugDownloaded(slug);

  void dispose() {
    _downloadController.close();
    _notifications.cancelAll();
  }
}

import 'dart:io' as io;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/models.dart';
import '../utils/utils.dart';

typedef NotificationTapCallback = void Function(String? payload);

class NotificationService with WidgetsBindingObserver {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static const String _downloadChannelId = 'download_progress';
  static const String _downloadChannelName = 'Download Progress';
  static const String _downloadChannelDesc = 'Shows download progress';

  static const String _completeChannelId = 'download_complete';
  static const String _completeChannelName = 'Download Complete';
  static const String _completeChannelDesc = 'Notifies when downloads complete';

  static const int _progressNotificationId = 1;

  bool _initialized = false;
  NotificationTapCallback? _onTapCallback;
  bool _isAppInForeground = true;

  Future<void> initialize() async {
    if (_initialized) return;

    // Register as lifecycle observer to track foreground/background state
    WidgetsBinding.instance.addObserver(this);

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create notification channels for Android
    if (io.Platform.isAndroid) {
      await _createNotificationChannels();
    }

    _initialized = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppInForeground = state == AppLifecycleState.resumed;
  }

  Future<void> _createNotificationChannels() async {
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidPlugin != null) {
      // Progress channel (silent, ongoing)
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _downloadChannelId,
          _downloadChannelName,
          description: _downloadChannelDesc,
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
        ),
      );

      // Complete channel (with sound)
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _completeChannelId,
          _completeChannelName,
          description: _completeChannelDesc,
          importance: Importance.high,
        ),
      );
    }
  }

  /// Set a callback to handle notification taps
  void setOnTapCallback(NotificationTapCallback callback) {
    _onTapCallback = callback;
  }

  void _onNotificationTap(NotificationResponse response) {
    // Invoke the callback with the payload (e.g., 'downloads' or 'library')
    _onTapCallback?.call(response.payload);
  }

  Future<bool> requestPermissions() async {
    if (io.Platform.isAndroid) {
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await androidPlugin?.requestNotificationsPermission();
      return granted ?? false;
    } else if (io.Platform.isIOS) {
      final iosPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final granted = await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    return false;
  }

  Future<void> showDownloadProgress({
    required String title,
    required double progress,
    required String progressText,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _downloadChannelId,
      _downloadChannelName,
      channelDescription: _downloadChannelDesc,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showProgress: true,
      maxProgress: 100,
      progress: (progress * 100).round(),
      onlyAlertOnce: true,
      icon: '@mipmap/ic_launcher',
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      _progressNotificationId,
      'Downloading',
      '$title - $progressText',
      notificationDetails,
      payload: 'downloads',
    );
  }

  Future<void> showExtracting({required String title}) async {
    final androidDetails = AndroidNotificationDetails(
      _downloadChannelId,
      _downloadChannelName,
      channelDescription: _downloadChannelDesc,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showProgress: true,
      indeterminate: true,
      onlyAlertOnce: true,
      icon: '@mipmap/ic_launcher',
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      _progressNotificationId,
      'Extracting',
      title,
      notificationDetails,
      payload: 'downloads',
    );
  }

  Future<void> showDownloadComplete({
    required String title,
    required String platform,
  }) async {
    // Cancel progress notification first
    await cancelProgressNotification();

    // Don't show completion notification if app is in foreground
    if (_isAppInForeground) return;

    final androidDetails = AndroidNotificationDetails(
      _completeChannelId,
      _completeChannelName,
      channelDescription: _completeChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    // Use unique ID for completed downloads
    final notificationId = DateTime.now().millisecondsSinceEpoch % 100000 + 100;

    await _notifications.show(
      notificationId,
      'Download Complete',
      '$title (${PlatformNames.getDisplayName(platform)})',
      notificationDetails,
      payload: 'library',
    );
  }

  Future<void> showDownloadFailed({
    required String title,
    String? error,
  }) async {
    await cancelProgressNotification();

    // Don't show failure notification if app is in foreground
    if (_isAppInForeground) return;

    final androidDetails = AndroidNotificationDetails(
      _completeChannelId,
      _completeChannelName,
      channelDescription: _completeChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    final notificationId = DateTime.now().millisecondsSinceEpoch % 100000 + 100;

    await _notifications.show(
      notificationId,
      'Download Failed',
      error != null ? '$title: $error' : title,
      notificationDetails,
      payload: 'downloads',
    );
  }

  Future<void> cancelProgressNotification() async {
    await _notifications.cancel(_progressNotificationId);
  }

  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }

  Future<void> updateForTask(DownloadTask task) async {
    switch (task.status) {
      case DownloadStatus.downloading:
        await showDownloadProgress(
          title: task.title,
          progress: task.progress,
          progressText: task.progressText,
        );
        break;
      case DownloadStatus.extracting:
        await showExtracting(title: task.title);
        break;
      case DownloadStatus.completed:
        await showDownloadComplete(title: task.title, platform: task.platform);
        break;
      case DownloadStatus.failed:
        await showDownloadFailed(title: task.title, error: task.error);
        break;
      case DownloadStatus.pending:
      case DownloadStatus.paused:
        await cancelProgressNotification();
        break;
    }
  }
}

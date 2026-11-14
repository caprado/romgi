import 'dart:async';

import '../models/download_link.dart';
import 'internet_archive_auth_manager.dart';

/// Per-host hooks that customize the HTTP download flow.
///
/// Adapters that handle a fundamentally different transport (currently
/// only [TorrentAdapter]) set [isTorrent] to true; the download service
/// routes those tasks through a separate path.
abstract class HostAdapter {
  bool get isTorrent => false;

  /// Inject host-specific request headers (auth, referer, ...).
  Future<void> prepareHeaders(
    Map<String, dynamic> headers,
    DownloadLink link,
  ) async {}

  /// Whether the download can proceed for [link] given current state
  /// (e.g. IA login). When this returns false the task fails fast with
  /// the message in [authError].
  Future<bool> canStartDownload(DownloadLink link) async => true;

  /// Stable error string shown to the user when [canStartDownload]
  /// returns false. Override only when relevant.
  String get authError => 'Authentication required';

  /// Called when a download fails with HTTP 401/403. Lets the adapter
  /// bump auth-failure counters / trigger re-auth flows.
  Future<void> onAuthFailure(DownloadLink link) async {}
}

class DefaultHttpAdapter extends HostAdapter {
  @override
  Future<void> prepareHeaders(
    Map<String, dynamic> headers,
    DownloadLink link,
  ) async {
    // Some hosts throttle non-browser User-Agents. The download service
    // sets a sane default; nothing else to do here.
  }
}

class InternetArchiveAdapter extends HostAdapter {
  InternetArchiveAdapter(this._auth);

  final IAAuthManager _auth;

  @override
  Future<bool> canStartDownload(DownloadLink link) async {
    if (!link.requiresAuth) return true;
    return _auth.isLoggedIn();
  }

  @override
  String get authError => 'Internet Archive login required';

  @override
  Future<void> prepareHeaders(
    Map<String, dynamic> headers,
    DownloadLink link,
  ) async {
    await _auth.ensureFresh();
    await _auth.applyHeaders(headers);
  }

  @override
  Future<void> onAuthFailure(DownloadLink link) async {
    await _auth.recordAuthFailure();
  }
}

class TorrentAdapter extends HostAdapter {
  @override
  bool get isTorrent => true;
}

/// Picks a [HostAdapter] for a [DownloadLink].
class HostAdapterRegistry {
  HostAdapterRegistry({
    HostAdapter? defaultHttp,
    HostAdapter? internetArchive,
    HostAdapter? torrent,
  })  : _defaultHttp = defaultHttp ?? DefaultHttpAdapter(),
        _internetArchive = internetArchive,
        _torrent = torrent ?? TorrentAdapter();

  final HostAdapter _defaultHttp;
  final HostAdapter? _internetArchive;
  final HostAdapter _torrent;

  HostAdapter adapterFor(DownloadLink link) {
    if (link.isTorrent) return _torrent;
    if (link.sourceId == 'internet_archive' ||
        IAAuthManager.isInternetArchiveUrl(link.url)) {
      return _internetArchive ?? _defaultHttp;
    }
    return _defaultHttp;
  }
}

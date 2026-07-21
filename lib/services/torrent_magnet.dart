/// Bundled into magnet URIs for libtorrent and the debrid fallback. HTTPS
/// first because some networks (and most Android emulators) block UDP.
const List<String> kPublicTrackers = <String>[
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

String buildMagnetUri(String infohash, {List<String>? trackers}) {
  final list = (trackers == null || trackers.isEmpty) ? kPublicTrackers : trackers;
  final parts = <String>['xt=urn:btih:$infohash'];
  for (final tracker in list) {
    parts.add('tr=${Uri.encodeQueryComponent(tracker)}');
  }
  return 'magnet:?${parts.join('&')}';
}

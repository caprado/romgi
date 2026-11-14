import 'package:flutter/services.dart';

class VpnService {
  static const _method = MethodChannel('com.caprado.romgi/network');
  static const _events = EventChannel('com.caprado.romgi/vpn');

  Future<bool> isActive() async {
    try {
      return await _method.invokeMethod<bool>('isVpnActive') ?? false;
    } catch (_) {
      return false;
    }
  }

  Stream<bool> get changes =>
      _events.receiveBroadcastStream().map((active) => active == true).distinct();
}

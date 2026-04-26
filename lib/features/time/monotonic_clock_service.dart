import 'package:flutter/services.dart';

class MonotonicClockService {
  static const MethodChannel _channel = MethodChannel('fussball/clock');

  Future<int> nowNs() async {
    final raw = await _channel.invokeMethod<int>('getElapsedRealtimeNanos');
    return raw ?? 0;
  }
}

import 'package:flutter/services.dart';

class PerformanceModeService {
  static const MethodChannel _channel = MethodChannel('fussball/performance_mode');

  Future<void> enableHighPerformanceMode() async {
    try {
      await _channel.invokeMethod<void>('enableHighPerformanceMode');
    } catch (_) {
      // Best-effort on non-Android or unsupported devices.
    }
  }

  Future<void> disableHighPerformanceMode() async {
    try {
      await _channel.invokeMethod<void>('disableHighPerformanceMode');
    } catch (_) {
      // Ignore cleanup failures.
    }
  }
}

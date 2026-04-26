import 'dart:async';

import 'package:flutter/services.dart';

class MotionDetectionSample {
  const MotionDetectionSample({
    required this.motionScore,
    required this.sensorTimestampNs,
    this.fps,
  });

  final double motionScore;
  final int sensorTimestampNs;
  final double? fps;
}

typedef MotionDetectedCallback = void Function(MotionDetectionSample sample);
typedef MotionFpsCallback = void Function(double fps);

class MotionDetectorService {
  MotionDetectorService({double initialThreshold = 0.22}) : _threshold = initialThreshold;

  static const MethodChannel _methodChannel = MethodChannel('fussball/motion_detection');
  static const EventChannel _eventChannel = EventChannel('fussball/motion_events');

  double _threshold;
  bool _monitoring = false;
  MotionDetectedCallback? _onMotionDetected;
  MotionFpsCallback? _onFps;
  StreamSubscription<dynamic>? _subscription;

  bool get monitoring => _monitoring;

  void setThreshold(double threshold) {
    _threshold = threshold;
    unawaited(
      _methodChannel.invokeMethod<void>('setThreshold', <String, dynamic>{'threshold': _threshold}),
    );
  }

  void setOnFps(MotionFpsCallback callback) {
    _onFps = callback;
  }

  Future<void> startMonitoring(MotionDetectedCallback onMotionDetected) async {
    _onMotionDetected = onMotionDetected;
    await _ensureSubscription();
    _monitoring = true;
    await _methodChannel.invokeMethod<void>('startMonitoring', <String, dynamic>{
      'threshold': _threshold,
    });
  }

  Future<void> stopMonitoring() async {
    _monitoring = false;
    await _methodChannel.invokeMethod<void>('stopMonitoring');
  }

  Future<void> _ensureSubscription() async {
    if (_subscription != null) {
      return;
    }

    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic raw) {
        if (raw is! Map) {
          return;
        }

        final data = Map<String, dynamic>.from(raw);
        final type = (data['type'] ?? '').toString();

        if (type == 'fps') {
          final fps = _asDouble(data['fps']);
          if (fps != null) {
            _onFps?.call(fps);
          }
          return;
        }

        if (type != 'motion' || !_monitoring) {
          return;
        }

        final motionScore = _asDouble(data['motionScore']);
        final sensorTimestampNs = _asInt(data['sensorTimestampNs']);
        if (motionScore == null || sensorTimestampNs == null) {
          return;
        }

        _onMotionDetected?.call(
          MotionDetectionSample(
            motionScore: motionScore,
            sensorTimestampNs: sensorTimestampNs,
            fps: _asDouble(data['fps']),
          ),
        );
      },
      onError: (_) {
        // Best-effort streaming for personal-project devices.
      },
    );
  }

  double? _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  Future<void> dispose() async {
    await stopMonitoring();
    await _subscription?.cancel();
    _subscription = null;
  }
}

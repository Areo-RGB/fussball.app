import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../shared/models/device_role.dart';
import '../../shared/protocol/message_type.dart';
import '../../shared/protocol/socket_envelope.dart';
import '../../shared/utils/time_format.dart';
import '../../shared/utils/trigger_cooldown_gate.dart';
import '../motion_detection/motion_detector_service.dart';
import '../network/client/client_connection.dart';
import '../network/device_identity.dart';
import '../performance/performance_mode_service.dart';
import '../permissions/permissions_service.dart';
import '../time/monotonic_clock_service.dart';

class ClientController extends ChangeNotifier {
  ClientController({
    PermissionsService? permissionsService,
    DeviceIdentityService? identityService,
    MotionDetectorService? motionDetectorService,
    PerformanceModeService? performanceModeService,
    MonotonicClockService? clockService,
  }) : _permissionsService = permissionsService ?? PermissionsService(),
       _identityService = identityService ?? DeviceIdentityService(),
       _motionDetectorService = motionDetectorService ?? MotionDetectorService(),
       _performanceModeService = performanceModeService ?? PerformanceModeService(),
       _clockService = clockService ?? MonotonicClockService() {
    _motionDetectorService.setOnFps(_onFpsUpdate);
  }

  final PermissionsService _permissionsService;
  final DeviceIdentityService _identityService;
  final MotionDetectorService _motionDetectorService;
  final PerformanceModeService _performanceModeService;
  final MonotonicClockService _clockService;
  final TriggerCooldownGate _cooldownGate = TriggerCooldownGate(cooldownMs: 300);

  DeviceIdentity? _identity;
  ClientConnection? _connection;
  String _sessionDeviceId = '';

  ClientConnectionState connectionState = ClientConnectionState.connecting;
  bool monitoring = false;
  DeviceRole role = DeviceRole.split;
  double sensitivity = 0.6;
  double lastMotionScore = 0;
  double? currentFps;
  String? errorText;

  String get identityLabel {
    final identity = _identity;
    if (identity == null) {
      return 'Loading device identity...';
    }
    return '${identity.manufacturer} ${identity.model}';
  }

  Future<void> initialize() async {
    await _performanceModeService.enableHighPerformanceMode();
    await _permissionsService.requestBroadPermissions();

    try {
      _identity = await _identityService.getIdentity();
      _sessionDeviceId = await _resolveSessionDeviceId(_identity!);
    } catch (error) {
      errorText = 'Failed to read device identity: $error';
      notifyListeners();
    }

    _connection = ClientConnection(
      onEnvelope: _onEnvelope,
      onStateChanged: _onConnectionStateChanged,
    );

    await _connection!.start();
  }

  void _onConnectionStateChanged(ClientConnectionState newState) {
    connectionState = newState;

    if (newState == ClientConnectionState.connected && _identity != null) {
      _sendHello();
    }

    notifyListeners();
  }

  void _sendHello() {
    final identity = _identity;
    if (identity == null) {
      return;
    }

    _connection?.send(
      type: MessageType.hello,
      deviceId: _sessionDeviceId,
      payload: <String, dynamic>{...identity.toJson(), 'lanIp': _sessionDeviceId},
    );
  }

  void _onEnvelope(SocketEnvelope envelope) {
    switch (envelope.type) {
      case MessageType.helloAck:
        role = parseRole(envelope.payload['role']?.toString());
        sensitivity = _asDouble(envelope.payload['sensitivity'], fallback: sensitivity);
        _motionDetectorService.setThreshold(_thresholdFromSensitivity(sensitivity));
        if (envelope.payload['monitoring'] == true) {
          unawaited(_setMonitoring(true));
        }
        break;
      case MessageType.roleSet:
        role = parseRole(envelope.payload['role']?.toString());
        break;
      case MessageType.sensitivitySet:
        sensitivity = _asDouble(envelope.payload['sensitivity'], fallback: sensitivity);
        _motionDetectorService.setThreshold(_thresholdFromSensitivity(sensitivity));
        break;
      case MessageType.monitoringStart:
        unawaited(_setMonitoring(true));
        break;
      case MessageType.monitoringStop:
        unawaited(_setMonitoring(false));
        break;
      case MessageType.ping:
        unawaited(_respondPong(envelope.payload));
        break;
      case MessageType.resetTimer:
        _cooldownGate.reset();
        break;
      default:
        break;
    }

    notifyListeners();
  }

  Future<void> _setMonitoring(bool active) async {
    if (active == monitoring) {
      return;
    }

    monitoring = active;
    _cooldownGate.reset();

    if (active) {
      await _motionDetectorService.startMonitoring(_onMotionDetected);
    } else {
      await _motionDetectorService.stopMonitoring();
    }

    notifyListeners();
  }

  void _onMotionDetected(MotionDetectionSample sample) {
    final identity = _identity;
    if (!monitoring || identity == null) {
      return;
    }

    final nowMs = (sample.sensorTimestampNs / 1000000).floor();
    if (!_cooldownGate.tryAcquire(nowMs)) {
      return;
    }

    lastMotionScore = sample.motionScore;

    _connection?.send(
      type: MessageType.trigger,
      payload: <String, dynamic>{
        'role': role.wireValue,
        'motionScore': sample.motionScore,
        'eventSensorTsNs': sample.sensorTimestampNs,
      },
    );

    notifyListeners();
  }

  void _onFpsUpdate(double fps) {
    currentFps = fps;
    _connection?.send(type: MessageType.telemetry, payload: <String, dynamic>{'fps': fps});
    notifyListeners();
  }

  Future<void> _respondPong(Map<String, dynamic> pingPayload) async {
    final pingId = (pingPayload['pingId'] ?? 'ping').toString();
    final sync = pingPayload['sync'] == true;
    final t1HostNs = _asInt(pingPayload['t1HostNs']) ?? 0;

    final t2ClientNs = await _clockService.nowNs();
    final t3ClientNs = await _clockService.nowNs();

    _connection?.send(
      type: MessageType.pong,
      payload: <String, dynamic>{
        'pingId': pingId,
        'sync': sync,
        't1HostNs': t1HostNs,
        't2ClientNs': t2ClientNs,
        't3ClientNs': t3ClientNs,
      },
    );
  }

  double _thresholdFromSensitivity(double value) {
    final clamped = value.clamp(0.0, 1.0);
    return 0.05 + ((1 - clamped) * 0.40);
  }

  double _asDouble(dynamic value, {required double fallback}) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? fallback;
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

  Future<void> close() async {
    await _motionDetectorService.dispose();
    await _connection?.close();
    await _performanceModeService.disableHighPerformanceMode();
  }

  String get lastMotionFormatted => formatElapsedMillisRoundUp((lastMotionScore * 1000).round());

  Future<String> _resolveSessionDeviceId(DeviceIdentity identity) async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final ip = address.address;
          if (ip.startsWith('192.168.')) {
            return ip;
          }
        }
      }
    } catch (_) {
      // Best-effort: fallback below.
    }
    return identity.deviceId;
  }
}

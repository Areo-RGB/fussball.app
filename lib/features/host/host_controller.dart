import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/models/connected_device.dart';
import '../../shared/models/device_role.dart';
import '../../shared/protocol/message_type.dart';
import '../../shared/protocol/socket_envelope.dart';
import '../../shared/utils/time_format.dart';
import '../network/host/host_server.dart';
import '../performance/performance_mode_service.dart';
import '../permissions/permissions_service.dart';
import '../time/monotonic_clock_service.dart';
import '../timer/timer_engine.dart';

class HostController extends ChangeNotifier {
  HostController({
    PermissionsService? permissionsService,
    PerformanceModeService? performanceModeService,
    MonotonicClockService? clockService,
  }) : _permissionsService = permissionsService ?? PermissionsService(),
       _performanceModeService = performanceModeService ?? PerformanceModeService(),
       _clockService = clockService ?? MonotonicClockService() {
    _server = HostServer(
      onMessage: _onMessage,
      onDeviceConnected: _onDeviceConnected,
      onDeviceDisconnected: _onDeviceDisconnected,
    );
  }

  final PermissionsService _permissionsService;
  final PerformanceModeService _performanceModeService;
  final MonotonicClockService _clockService;
  final TimerEngine timerEngine = TimerEngine();
  late final HostServer _server;

  final Map<String, ConnectedDevice> _devices = <String, ConnectedDevice>{};
  final Map<String, _PendingPing> _pendingPings = <String, _PendingPing>{};
  final Map<String, List<_SyncSample>> _syncSamples = <String, List<_SyncSample>>{};
  final Set<String> _syncingDevices = <String>{};

  bool monitoringArmed = false;
  int _nowMs = DateTime.now().millisecondsSinceEpoch;
  int? _visualStartAtMs;
  Timer? _ticker;
  int _pingCounter = 0;

  List<ConnectedDevice> get devices =>
      _devices.values.where((device) => device.connected).toList(growable: false);

  String get timerDisplay {
    if (timerEngine.state == TimerRunState.stopped) {
      return formatElapsedMillisRoundUp(timerEngine.finalElapsedMs);
    }

    if (timerEngine.state == TimerRunState.running && _visualStartAtMs != null) {
      final elapsed = _nowMs - _visualStartAtMs!;
      return formatElapsedMillisRoundUp(elapsed < 0 ? 0 : elapsed);
    }

    return '0.00s';
  }

  Future<void> initialize() async {
    await _performanceModeService.enableHighPerformanceMode();
    await _permissionsService.requestBroadPermissions();
    _startTicker();
    await _server.start();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (timerEngine.state == TimerRunState.running) {
        _nowMs = DateTime.now().millisecondsSinceEpoch;
        notifyListeners();
      }
    });
  }

  void _onDeviceConnected(String deviceId) {
    final existing = _devices[deviceId];
    if (existing != null) {
      _devices[deviceId] = existing.copyWith(connected: true);
      notifyListeners();
    }
  }

  void _onDeviceDisconnected(String deviceId) {
    final existing = _devices[deviceId];
    if (existing != null) {
      _devices[deviceId] = existing.copyWith(connected: false, synced: false, clearLatency: true);
      notifyListeners();
    }
  }

  void _onMessage(String deviceId, SocketEnvelope envelope, int receivedAtMs) {
    switch (envelope.type) {
      case MessageType.hello:
        _registerOrUpdateDevice(deviceId, envelope);
        break;
      case MessageType.trigger:
        _handleTrigger(deviceId: deviceId, envelope: envelope, receivedAtMs: receivedAtMs);
        break;
      case MessageType.pong:
        unawaited(_handlePong(deviceId, envelope.payload));
        break;
      default:
        break;
    }

    _nowMs = receivedAtMs;
    notifyListeners();
  }

  void _registerOrUpdateDevice(String deviceId, SocketEnvelope envelope) {
    if (deviceId.isEmpty) {
      return;
    }

    final manufacturer = (envelope.payload['manufacturer'] ?? 'Unknown').toString();
    final model = (envelope.payload['model'] ?? 'Unknown').toString();
    final device = (envelope.payload['device'] ?? 'Unknown').toString();

    final existing = _devices[deviceId];
    final assignedRole = existing?.role ?? _autoRoleForNewDevice();
    final sensitivity = existing?.sensitivity ?? 0.6;

    _devices[deviceId] = ConnectedDevice(
      deviceId: deviceId,
      manufacturer: manufacturer,
      model: model,
      device: device,
      role: assignedRole,
      sensitivity: sensitivity,
      latencyMs: existing?.latencyMs,
      synced: existing?.synced ?? false,
      offsetNs: existing?.offsetNs ?? 0,
      lastSyncAtMs: existing?.lastSyncAtMs,
      currentFps: existing?.currentFps,
      connected: true,
    );

    _sendToDevice(
      deviceId: deviceId,
      type: MessageType.helloAck,
      payload: <String, dynamic>{
        'role': assignedRole.wireValue,
        'sensitivity': sensitivity,
        'monitoring': monitoringArmed,
      },
    );

    unawaited(_startSyncSession(deviceId));
  }

  DeviceRole _autoRoleForNewDevice() {
    final connectedCount = _devices.values.where((d) => d.connected).length;
    if (connectedCount == 0) {
      return DeviceRole.start;
    }
    if (connectedCount == 1) {
      return DeviceRole.stop;
    }
    return DeviceRole.split;
  }

  Future<void> _startSyncSession(String deviceId, {bool diagnostics = false}) async {
    if (_syncingDevices.contains(deviceId)) {
      return;
    }

    final existing = _devices[deviceId];
    if (existing == null || !existing.connected) {
      return;
    }

    _syncingDevices.add(deviceId);
    _syncSamples[deviceId] = <_SyncSample>[];
    _devices[deviceId] = existing.copyWith(
      synced: false,
      clearLatency: diagnostics,
      clearCurrentFps: diagnostics,
    );
    notifyListeners();

    try {
      for (var sampleIndex = 0; sampleIndex < 10; sampleIndex++) {
        if (!(_devices[deviceId]?.connected ?? false)) {
          break;
        }

        final t1HostNs = await _clockService.nowNs();
        final pingId = '${deviceId}_${_pingCounter++}_$t1HostNs';
        _pendingPings[pingId] = _PendingPing(
          deviceId: deviceId,
          t1HostNs: t1HostNs,
          sync: true,
          diagnostics: diagnostics,
        );

        _sendToDevice(
          deviceId: deviceId,
          type: MessageType.ping,
          payload: <String, dynamic>{
            'pingId': pingId,
            'sync': true,
            'diagnostics': diagnostics,
            'sampleIndex': sampleIndex,
            'sampleCount': 10,
            't1HostNs': t1HostNs,
          },
        );

        await Future<void>.delayed(const Duration(milliseconds: 35));
      }

      await Future<void>.delayed(const Duration(milliseconds: 500));
      _finalizeSync(deviceId);
    } finally {
      _syncingDevices.remove(deviceId);
      notifyListeners();
    }
  }

  void _finalizeSync(String deviceId) {
    final samples = _syncSamples[deviceId];
    final existing = _devices[deviceId];
    if (samples == null || samples.isEmpty || existing == null) {
      return;
    }

    var best = samples.first;
    for (final sample in samples.skip(1)) {
      if (sample.rttNs < best.rttNs) {
        best = sample;
      }
    }

    final latencyMs = (best.rttNs / 1000000).round();
    final synced = latencyMs <= 20;

    _devices[deviceId] = existing.copyWith(
      latencyMs: latencyMs,
      synced: synced,
      offsetNs: best.offsetNs,
      lastSyncAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void _handleTrigger({
    required String deviceId,
    required SocketEnvelope envelope,
    required int receivedAtMs,
  }) {
    final device = _devices[deviceId];
    if (device == null || !device.connected) {
      return;
    }

    final eventSensorTsNs = _asInt(envelope.payload['eventSensorTsNs']);
    if (eventSensorTsNs == null) {
      return;
    }

    final eventHostNs = eventSensorTsNs - device.offsetNs;

    switch (device.role) {
      case DeviceRole.start:
        if (timerEngine.state == TimerRunState.idle) {
          timerEngine.start(eventHostNs);
          _visualStartAtMs = receivedAtMs;
        }
        break;
      case DeviceRole.stop:
        if (timerEngine.state == TimerRunState.running) {
          timerEngine.stop(eventHostNs);
        }
        break;
      case DeviceRole.split:
        if (timerEngine.state == TimerRunState.running) {
          timerEngine.addSplit(
            deviceId: device.deviceId,
            deviceName: device.displayName,
            atNs: eventHostNs,
          );
        }
        break;
    }
  }

  Future<void> _handlePong(String deviceId, Map<String, dynamic> payload) async {
    final pingId = payload['pingId']?.toString();
    if (pingId == null) {
      return;
    }

    final pending = _pendingPings.remove(pingId);
    if (pending == null || pending.deviceId != deviceId || !pending.sync) {
      return;
    }

    final t2ClientNs = _asInt(payload['t2ClientNs']);
    final t3ClientNs = _asInt(payload['t3ClientNs']);
    if (t2ClientNs == null || t3ClientNs == null) {
      return;
    }

    final t4HostNs = await _clockService.nowNs();
    final rttNs = (t4HostNs - pending.t1HostNs) - (t3ClientNs - t2ClientNs);
    final offsetNs = ((t2ClientNs - pending.t1HostNs) + (t3ClientNs - t4HostNs)) ~/ 2;

    if (rttNs <= 0) {
      return;
    }

    _syncSamples
        .putIfAbsent(deviceId, () => <_SyncSample>[])
        .add(_SyncSample(rttNs: rttNs, offsetNs: offsetNs));

    if (pending.diagnostics) {
      final existing = _devices[deviceId];
      final fps = _asDouble(payload['fps']);
      if (existing != null && fps != null) {
        _devices[deviceId] = existing.copyWith(currentFps: fps);
      }
    }

    if (_syncSamples[deviceId]!.length >= 10) {
      _finalizeSync(deviceId);
    }
  }

  void setRole(String deviceId, DeviceRole role) {
    final existing = _devices[deviceId];
    if (existing == null) {
      return;
    }

    _devices[deviceId] = existing.copyWith(role: role);
    _sendToDevice(
      deviceId: deviceId,
      type: MessageType.roleSet,
      payload: <String, dynamic>{'role': role.wireValue},
    );
    notifyListeners();
  }

  void setSensitivity(String deviceId, double sensitivity) {
    final existing = _devices[deviceId];
    if (existing == null) {
      return;
    }

    final clamped = sensitivity.clamp(0.0, 1.0);
    _devices[deviceId] = existing.copyWith(sensitivity: clamped);
    _sendToDevice(
      deviceId: deviceId,
      type: MessageType.sensitivitySet,
      payload: <String, dynamic>{'sensitivity': clamped},
    );
    notifyListeners();
  }

  void testLatency(String deviceId) {
    unawaited(_startSyncSession(deviceId, diagnostics: true));
  }

  Future<void> startMonitoring() async {
    monitoringArmed = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _broadcast(type: MessageType.monitoringStart, payload: const <String, dynamic>{});
  }

  void stopMonitoring() {
    monitoringArmed = false;
    _broadcast(type: MessageType.monitoringStop, payload: const <String, dynamic>{});
    notifyListeners();
  }

  void resetTimer() {
    timerEngine.reset();
    _visualStartAtMs = null;
    _nowMs = DateTime.now().millisecondsSinceEpoch;
    _broadcast(type: MessageType.resetTimer, payload: const <String, dynamic>{});

    for (final device in devices) {
      unawaited(_startSyncSession(device.deviceId));
    }

    notifyListeners();
  }

  void _sendToDevice({
    required String deviceId,
    required String type,
    required Map<String, dynamic> payload,
  }) {
    _server.sendToDevice(
      deviceId,
      SocketEnvelope(
        type: type,
        deviceId: 'host',
        sentAtMs: DateTime.now().millisecondsSinceEpoch,
        seq: 0,
        payload: payload,
      ),
    );
  }

  void _broadcast({required String type, required Map<String, dynamic> payload}) {
    _server.broadcast(
      SocketEnvelope(
        type: type,
        deviceId: 'host',
        sentAtMs: DateTime.now().millisecondsSinceEpoch,
        seq: 0,
        payload: payload,
      ),
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

  Future<void> close() async {
    _ticker?.cancel();
    await _server.stop();
    await _performanceModeService.disableHighPerformanceMode();
  }
}

class _PendingPing {
  const _PendingPing({
    required this.deviceId,
    required this.t1HostNs,
    required this.sync,
    required this.diagnostics,
  });

  final String deviceId;
  final int t1HostNs;
  final bool sync;
  final bool diagnostics;
}

class _SyncSample {
  const _SyncSample({required this.rttNs, required this.offsetNs});

  final int rttNs;
  final int offsetNs;
}

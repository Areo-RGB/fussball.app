import 'device_role.dart';

class ConnectedDevice {
  const ConnectedDevice({
    required this.deviceId,
    required this.manufacturer,
    required this.model,
    required this.device,
    required this.role,
    required this.sensitivity,
    this.latencyMs,
    this.synced = false,
    this.offsetNs = 0,
    this.lastSyncAtMs,
    this.currentFps,
    this.connected = true,
  });

  final String deviceId;
  final String manufacturer;
  final String model;
  final String device;
  final DeviceRole role;
  final double sensitivity;
  final int? latencyMs;
  final bool synced;
  final int offsetNs;
  final int? lastSyncAtMs;
  final double? currentFps;
  final bool connected;

  String get displayName => '$manufacturer $model';

  ConnectedDevice copyWith({
    String? deviceId,
    String? manufacturer,
    String? model,
    String? device,
    DeviceRole? role,
    double? sensitivity,
    int? latencyMs,
    bool clearLatency = false,
    bool? synced,
    int? offsetNs,
    int? lastSyncAtMs,
    bool clearLastSync = false,
    double? currentFps,
    bool clearCurrentFps = false,
    bool? connected,
  }) {
    return ConnectedDevice(
      deviceId: deviceId ?? this.deviceId,
      manufacturer: manufacturer ?? this.manufacturer,
      model: model ?? this.model,
      device: device ?? this.device,
      role: role ?? this.role,
      sensitivity: sensitivity ?? this.sensitivity,
      latencyMs: clearLatency ? null : (latencyMs ?? this.latencyMs),
      synced: synced ?? this.synced,
      offsetNs: offsetNs ?? this.offsetNs,
      lastSyncAtMs: clearLastSync ? null : (lastSyncAtMs ?? this.lastSyncAtMs),
      currentFps: clearCurrentFps ? null : (currentFps ?? this.currentFps),
      connected: connected ?? this.connected,
    );
  }
}

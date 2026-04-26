import 'package:flutter/services.dart';

class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.manufacturer,
    required this.model,
    required this.device,
  });

  final String deviceId;
  final String manufacturer;
  final String model;
  final String device;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'deviceId': deviceId,
      'manufacturer': manufacturer,
      'model': model,
      'device': device,
    };
  }
}

class DeviceIdentityService {
  static const MethodChannel _channel = MethodChannel('fussball/device_identity');

  Future<DeviceIdentity> getIdentity() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('getDeviceIdentity');
    final manufacturer = (raw?['manufacturer'] ?? 'Unknown').toString();
    final model = (raw?['model'] ?? 'Unknown').toString();
    final device = (raw?['device'] ?? 'Unknown').toString();
    final androidId = (raw?['androidId'] ?? 'unknown_android_id').toString();

    final cleanDeviceId = '$manufacturer-$model-$androidId'
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();

    return DeviceIdentity(
      deviceId: cleanDeviceId,
      manufacturer: manufacturer,
      model: model,
      device: device,
    );
  }
}

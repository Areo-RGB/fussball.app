import 'package:permission_handler/permission_handler.dart';

class PermissionsService {
  Future<void> requestBroadPermissions() async {
    final requested = <Permission>[
      Permission.camera,
      Permission.microphone,
      Permission.storage,
      Permission.photos,
      Permission.videos,
      Permission.audio,
      Permission.locationWhenInUse,
      Permission.locationAlways,
      Permission.notification,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.ignoreBatteryOptimizations,
    ];

    try {
      await requested.request();
    } catch (_) {
      // Best-effort permissions for personal setup.
    }
  }
}

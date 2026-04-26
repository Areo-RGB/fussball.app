# Fussball LAN Sprint Timer

Host/client flavored Flutter app for local sprint timing with camera-based motion detection.

## Run

Host flavor:

```powershell
flutter run --flavor host -t lib/main_host.dart
```

Client flavor:

```powershell
flutter run --flavor client -t lib/main_client.dart
```

## Build

```powershell
flutter build apk --flavor host -t lib/main_host.dart
flutter build apk --flavor client -t lib/main_client.dart
```

## Install via ADB

```powershell
.\scripts\install_flavors.ps1 -HostSerial 4c637b9e
```

## Notes

- Host WebSocket endpoint is hardcoded to `ws://192.168.0.103:8080`.
- Timer uses host receive time.
- Client motion detection checks center 3% ROI from luma plane and applies 300ms trigger cooldown.

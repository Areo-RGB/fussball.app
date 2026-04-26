# Install host/client flavor APKs on connected devices and grant broad permissions.

param(
  [string]$HostSerial = "4c637b9e"
)

$ErrorActionPreference = "Stop"

Write-Host "Building host flavor APK..."
flutter build apk --flavor host -t lib/main_host.dart

Write-Host "Building client flavor APK..."
flutter build apk --flavor client -t lib/main_client.dart

$hostApk = "build/app/outputs/flutter-apk/app-host-release.apk"
$clientApk = "build/app/outputs/flutter-apk/app-client-release.apk"

if (!(Test-Path $hostApk) -or !(Test-Path $clientApk)) {
  throw "Expected APKs were not found."
}

$deviceLines = adb devices | Select-String "\tdevice$"
$serials = @()
foreach ($line in $deviceLines) {
  $serials += ($line.ToString().Split("`t")[0])
}

if ($serials.Count -eq 0) {
  throw "No ADB devices are connected."
}

$hostPackage = "com.example.fussball_app.host"
$clientPackage = "com.example.fussball_app.client"

$permissions = @(
  "android.permission.CAMERA",
  "android.permission.RECORD_AUDIO",
  "android.permission.ACCESS_FINE_LOCATION",
  "android.permission.ACCESS_COARSE_LOCATION",
  "android.permission.ACCESS_BACKGROUND_LOCATION",
  "android.permission.POST_NOTIFICATIONS",
  "android.permission.READ_EXTERNAL_STORAGE",
  "android.permission.WRITE_EXTERNAL_STORAGE",
  "android.permission.READ_MEDIA_IMAGES",
  "android.permission.READ_MEDIA_VIDEO",
  "android.permission.READ_MEDIA_AUDIO",
  "android.permission.BLUETOOTH_CONNECT",
  "android.permission.BLUETOOTH_SCAN",
  "android.permission.BLUETOOTH_ADVERTISE"
)

function Grant-Permissions {
  param(
    [string]$Serial,
    [string]$PackageName
  )

  foreach ($permission in $permissions) {
    adb -s $Serial shell pm grant $PackageName $permission 2>$null | Out-Null
  }
}

foreach ($serial in $serials) {
  if ($serial -eq $HostSerial) {
    Write-Host "Installing HOST APK to $serial"
    adb -s $serial install -r -g $hostApk
    Grant-Permissions -Serial $serial -PackageName $hostPackage
  }
  else {
    Write-Host "Installing CLIENT APK to $serial"
    adb -s $serial install -r -g $clientApk
    Grant-Permissions -Serial $serial -PackageName $clientPackage
  }
}

Write-Host "Done."

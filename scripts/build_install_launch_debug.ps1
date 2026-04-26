# Build, uninstall old installs, install debug APKs, and launch host/client apps.

param(
  [string]$HostSerial = "4c637b9e"
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

$hostPackage = "com.example.fussball_app.host"
$clientPackage = "com.example.fussball_app.client"
$hostApk = Join-Path $ProjectRoot "build\\app\\outputs\\flutter-apk\\app-host-debug.apk"
$clientApk = Join-Path $ProjectRoot "build\\app\\outputs\\flutter-apk\\app-client-debug.apk"

Write-Host "Building host debug APK..."
flutter build apk --debug --flavor host -t lib/main_host.dart

Write-Host "Building client debug APK..."
flutter build apk --debug --flavor client -t lib/main_client.dart

if (!(Test-Path $hostApk) -or !(Test-Path $clientApk)) {
  throw "Expected debug APKs not found in build output."
}

$deviceLines = adb devices | Select-String "\tdevice$"
$serials = @()
foreach ($line in $deviceLines) {
  $serials += ($line.ToString().Split("`t")[0])
}

if ($serials.Count -eq 0) {
  throw "No ADB devices are connected."
}

function Try-Uninstall {
  param(
    [string]$Serial,
    [string]$PackageName
  )

  adb -s $Serial uninstall $PackageName 2>$null | Out-Null
}

function Install-And-Launch {
  param(
    [string]$Serial,
    [string]$Apk,
    [string]$PackageName,
    [string]$Role
  )

  Write-Host "[$Role] device=$Serial uninstall old package"
  Try-Uninstall -Serial $Serial -PackageName $PackageName

  Write-Host "[$Role] device=$Serial install $Apk"
  adb -s $Serial install -r -g $Apk

  Write-Host "[$Role] device=$Serial launch $PackageName"
  adb -s $Serial shell monkey -p $PackageName -c android.intent.category.LAUNCHER 1 | Out-Null
}

foreach ($serial in $serials) {
  if ($serial -eq $HostSerial) {
    Install-And-Launch -Serial $serial -Apk $hostApk -PackageName $hostPackage -Role "HOST"
  }
  else {
    Install-And-Launch -Serial $serial -Apk $clientApk -PackageName $clientPackage -Role "CLIENT"
  }
}

Write-Host "Build + uninstall + install + launch completed."

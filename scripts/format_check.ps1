# Check formatting without changing files.

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

dart format --set-exit-if-changed lib test scripts

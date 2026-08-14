# Requires: Flutter Android toolchain, JDK 17+ and a private android/key.properties.
# Run from PowerShell: .\tools\release_android.ps1
[CmdletBinding()]
param(
  [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

function Require-Command([string]$Name, [string]$Hint) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "$Name was not found. $Hint"
  }
}

Require-Command 'flutter' 'Install Flutter with the Android toolchain and add <flutter>\bin to PATH.'
Require-Command 'fastforge' 'Run: dart pub global activate fastforge; then add %APPDATA%\Pub\Cache\bin to PATH.'

$keyProperties = Join-Path $ProjectRoot 'android\key.properties'
if (-not (Test-Path $keyProperties)) {
  throw 'Missing android\key.properties. Copy android\key.properties.example, create a private release keystore, and configure its real values before a production build.'
}

Write-Host '==> Resolving Flutter dependencies'
flutter pub get

Write-Host '==> Running release quality gate'
flutter analyze
if (-not $SkipTests) {
  flutter test
}

Write-Host '==> Packaging signed Android APK and AAB with Fastforge'
fastforge package --platform android --targets apk,aab
if ($LASTEXITCODE -ne 0) { throw 'Fastforge Android package failed.' }

$artifacts = Get-ChildItem -Path (Join-Path $ProjectRoot 'dist') -Recurse -File |
  Where-Object { $_.Extension -in '.apk', '.aab' } |
  Sort-Object Name
if (-not $artifacts) { throw 'No Android APK/AAB was found under dist/.' }

$manifest = Join-Path $ProjectRoot 'dist\SHA256SUMS.txt'
$lines = foreach ($artifact in $artifacts) {
  $hash = (Get-FileHash -Algorithm SHA256 $artifact.FullName).Hash.ToLowerInvariant()
  "$hash  $($artifact.Name)"
}
$lines | Set-Content -Path $manifest -Encoding utf8

Write-Host "==> Release ready"
$artifacts | ForEach-Object { Write-Host "    $($_.FullName)" }
Write-Host "    $manifest"

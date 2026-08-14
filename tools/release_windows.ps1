# Requires: Windows, Flutter Windows toolchain, Fastforge 0.6.x and Inno Setup 6.
# Run from PowerShell: .\tools\release_windows.ps1
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

Require-Command 'flutter' 'Install Flutter and add <flutter>\bin to PATH.'
Require-Command 'fastforge' 'Run: dart pub global activate fastforge; then add %APPDATA%\Pub\Cache\bin to PATH.'

$innoDefault = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
if (-not $env:INNO_SETUP_PATH -and -not (Test-Path $innoDefault) -and -not (Get-Command 'iscc' -ErrorAction SilentlyContinue)) {
  throw 'Inno Setup 6 was not found. Install it or set INNO_SETUP_PATH to its installation directory.'
}

Write-Host '==> Resolving Flutter dependencies'
flutter pub get

Write-Host '==> Running release quality gate'
flutter analyze
if (-not $SkipTests) {
  flutter test
}

Write-Host '==> Packaging Windows EXE installer with Fastforge'
# Fastforge invokes the Flutter Windows Release build and Inno Setup using
# windows/packaging/exe/make_config.yaml.
fastforge package --platform windows --targets exe
if ($LASTEXITCODE -ne 0) { throw 'Fastforge Windows package failed.' }

$artifacts = Get-ChildItem -Path (Join-Path $ProjectRoot 'dist') -Recurse -File -Filter '*.exe' |
  Sort-Object LastWriteTime -Descending
if (-not $artifacts) { throw 'No Windows installer (.exe) was found under dist/.' }

$manifest = Join-Path $ProjectRoot 'dist\SHA256SUMS.txt'
$lines = foreach ($artifact in $artifacts) {
  $hash = (Get-FileHash -Algorithm SHA256 $artifact.FullName).Hash.ToLowerInvariant()
  "$hash  $($artifact.Name)"
}
$lines | Set-Content -Path $manifest -Encoding utf8

Write-Host "==> Release ready"
$artifacts | ForEach-Object { Write-Host "    $($_.FullName)" }
Write-Host "    $manifest"

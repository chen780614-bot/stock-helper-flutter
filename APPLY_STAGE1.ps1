$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:PATH = "C:\flutter\bin;$env:PATH"
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "C:\Users\user\AppData\Local\Android\Sdk"

$root = "C:\Users\user\Documents\stock-helper-flutter"
$patchRoot = $PSScriptRoot
if (-not (Test-Path -LiteralPath $root)) { throw "Missing project: $root" }

Write-Host "== Stage 1 securities sync harden =="

# Ensure branch
Set-Location $root
git rev-parse --is-inside-work-tree 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
  $cur = git branch --show-current
  if ($cur -ne "stage1-securities-sync") {
    git checkout -B stage1-securities-sync 2>$null
    if ($LASTEXITCODE -ne 0) { git checkout -b stage1-securities-sync }
  }
}

$secDst = Join-Path $root "lib\services\securities"
New-Item -ItemType Directory -Force -Path $secDst | Out-Null
Copy-Item -Force (Join-Path $patchRoot "lib\services\securities\*.dart") $secDst
Copy-Item -Force (Join-Path $patchRoot "lib\services\names.dart") (Join-Path $root "lib\services\names.dart")
Copy-Item -Force (Join-Path $patchRoot "lib\screens\settings_screen.dart") (Join-Path $root "lib\screens\settings_screen.dart")
Copy-Item -Force (Join-Path $patchRoot "lib\main.dart") (Join-Path $root "lib\main.dart")
$testDst = Join-Path $root "test"
New-Item -ItemType Directory -Force -Path $testDst | Out-Null
Copy-Item -Force (Join-Path $patchRoot "test\securities_sync_stage1_test.dart") $testDst

Set-Location $root
Write-Host "== flutter pub get =="
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "pub get failed" }

Write-Host "== flutter analyze (lib + test) =="
flutter analyze lib test/securities_sync_stage1_test.dart
if ($LASTEXITCODE -ne 0) { throw "analyze failed" }

Write-Host "== flutter test securities_sync_stage1_test =="
flutter test test/securities_sync_stage1_test.dart
if ($LASTEXITCODE -ne 0) { throw "test failed" }

Write-Host "== git commit Stage 1 =="
git add lib/services/securities lib/services/names.dart lib/screens/settings_screen.dart lib/main.dart test/securities_sync_stage1_test.dart
git status -sb
git commit -m @"
Stage 1: harden TW securities sync (per-market staging + validation).

Per-market TWSE/TPEx/Emerging sync with staging/validation/transactions;
never wipe good data on bad fetches; persist sync status; settings UI;
unit tests. Schema bump securities DB v1 -> v2 (market_sync_meta).
"@

Write-Host "STAGE1_OK"
git rev-parse HEAD
git branch --show-current

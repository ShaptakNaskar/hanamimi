# Hanamimi+ — one-shot Windows build (ARCHITECTURE-DESKTOP.md §7).
#
# Run from an elevated PowerShell in the repo root:
#   Set-ExecutionPolicy -Scope Process Bypass
#   .\packaging\windows\build-windows.ps1
#
# Installs missing prerequisites via winget (Git, Flutter 3.29.3,
# VS 2022 Build Tools C++ workload, Rust — smtc_windows compiles a
# Rust crate), then builds the release exe and bundles yt-dlp + ffmpeg
# next to it. Output: dist\hanamimi-windows\ (portable folder with
# hanamimi.exe) + dist\hanamimi-windows.zip.
#
# IMPORTANT: Windows "Developer Mode" must be ON (Settings → System →
# For developers) — Flutter needs symlink support for plugins.
$ErrorActionPreference = 'Stop'

function Have($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

Write-Host "== Prerequisites ==" -ForegroundColor Cyan

if (-not (Have git)) {
  Write-Host "Installing Git..."
  winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
}

if (-not (Have cargo)) {
  Write-Host "Installing Rust (needed by smtc_windows)..."
  winget install --id Rustlang.Rustup -e --accept-source-agreements --accept-package-agreements
  $env:Path += ";$env:USERPROFILE\.cargo\bin"
}

# VS Build Tools with the C++ workload (MSVC + CMake + Ninja).
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$hasVc = (Test-Path $vswhere) -and
  ((& $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format value -property installationPath) -ne $null)
if (-not $hasVc) {
  Write-Host "Installing VS 2022 Build Tools (C++ workload) — this is the big one..."
  winget install --id Microsoft.VisualStudio.2022.BuildTools -e `
    --override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended" `
    --accept-source-agreements --accept-package-agreements
}

if (-not (Have flutter)) {
  Write-Host "Installing Flutter 3.29.3..."
  $flutterDir = "$env:USERPROFILE\flutter"
  if (-not (Test-Path $flutterDir)) {
    git clone --depth 1 --branch 3.29.3 https://github.com/flutter/flutter.git $flutterDir
  }
  $env:Path += ";$flutterDir\bin"
}

flutter config --enable-windows-desktop | Out-Null
flutter doctor

Write-Host "== Building ==" -ForegroundColor Cyan
flutter pub get
flutter build windows --release

$release = "build\windows\x64\runner\Release"
if (-not (Test-Path "$release\hanamimi.exe")) { throw "Build output missing at $release" }

Write-Host "== Bundling helpers ==" -ForegroundColor Cyan
# The app can lazy-fetch these itself on first run, but bundling makes
# the very first launch fully offline-capable.
Invoke-WebRequest https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe `
  -OutFile "$release\yt-dlp.exe"
Invoke-WebRequest https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip `
  -OutFile "$env:TEMP\ffmpeg.zip"
Expand-Archive -Force "$env:TEMP\ffmpeg.zip" "$env:TEMP\ffmpeg-x"
Copy-Item "$env:TEMP\ffmpeg-x\*\bin\ffmpeg.exe"  "$release\"
Copy-Item "$env:TEMP\ffmpeg-x\*\bin\ffprobe.exe" "$release\"
Remove-Item -Recurse -Force "$env:TEMP\ffmpeg-x", "$env:TEMP\ffmpeg.zip"

Copy-Item packaging\windows\test-smtc.ps1 "$release\"
Copy-Item packaging\windows\TESTING.md    "$release\"

New-Item -ItemType Directory -Force dist | Out-Null
$out = "dist\hanamimi-windows"
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
Copy-Item -Recurse $release $out
Compress-Archive -Force "$out\*" "dist\hanamimi-windows.zip"

Write-Host "`nDone → $out\hanamimi.exe  (zip: dist\hanamimi-windows.zip)" -ForegroundColor Green
Write-Host "Test with: cd $out; .\test-smtc.ps1"

# Hanamimi+ -- SMTC / media-key test suite for the Windows box.
#
# Run next to hanamimi.exe:   .\test-smtc.ps1
#
# What it does:
#  1. Launches the app if it isn't running.
#  2. Reads Windows' own SMTC session list (the same source the media
#     flyout and lock screen use) and verifies Hanamimi registered.
#  3. Synthesizes hardware media keys ON THIS MACHINE (keybd_event),
#     so it works over Parsec even though Parsec may not forward your
#     real media keys, and checks the SMTC playback state flips.
#
# PASS/FAIL prints per step; manual checks are listed in TESTING.md.
#
# NOTE: ASCII-only on purpose (PowerShell 5.1 ANSI parsing).
$ErrorActionPreference = 'SilentlyContinue'

# --- WinRT async helper (PowerShell 5-compatible) ---
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
  Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($winrtTask, $resultType) {
  $asTask = $asTaskGeneric.MakeGenericMethod($resultType)
  $netTask = $asTask.Invoke($null, @($winrtTask))
  $netTask.Wait(-1) | Out-Null
  $netTask.Result
}
[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime] | Out-Null

function Get-HanamimiSession {
  $mgr = Await ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) `
    ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
  $mgr.GetSessions() | Where-Object { $_.SourceAppUserModelId -match 'hanamimi' } | Select-Object -First 1
}

function Get-State {
  $s = Get-HanamimiSession
  if (-not $s) { return $null }
  $props = Await ($s.TryGetMediaPropertiesAsync()) `
    ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
  [pscustomobject]@{
    Status = $s.GetPlaybackInfo().PlaybackStatus  # Playing / Paused / Stopped
    Title  = $props.Title
    Artist = $props.Artist
  }
}

# --- Synthetic hardware media keys ---
$kb = Add-Type -PassThru -Name KB -Namespace Win32 -MemberDefinition `
  '[DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo);'
function Press-MediaKey($vk) {
  $kb::keybd_event($vk, 0, 1, 0)   # extended key down
  Start-Sleep -Milliseconds 80
  $kb::keybd_event($vk, 0, 3, 0)   # extended key up
}
$VK_PLAYPAUSE = 0xB3; $VK_NEXT = 0xB0; $VK_PREV = 0xB1

$results = [ordered]@{}
function Check($name, $ok, $detail) {
  $results[$name] = $ok
  $tag = if ($ok) { 'PASS' } else { 'FAIL' }
  $color = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("[{0}] {1}  {2}" -f $tag, $name, $detail) -ForegroundColor $color
}

# --- 1. App running ---
if (-not (Get-Process hanamimi -ErrorAction SilentlyContinue)) {
  Write-Host 'Starting hanamimi.exe...'
  Start-Process (Join-Path $PSScriptRoot 'hanamimi.exe')
  Start-Sleep 8
}
Check 'app process' ([bool](Get-Process hanamimi -ErrorAction SilentlyContinue)) ''

Write-Host ''
Write-Host '>> In the app: click a song so playback starts, then press Enter here.' -ForegroundColor Yellow
Read-Host | Out-Null

# --- 2. SMTC session registered ---
$state = Get-State
if ($state) {
  Check 'SMTC session registered' $true "now playing: $($state.Title) - $($state.Artist) [$($state.Status)]"
} else {
  Check 'SMTC session registered' $false 'no session found - SMTC init failed'
  Write-Host ''
  Write-Host 'Remaining checks need the session - aborting.' -ForegroundColor Red
  exit 1
}
Check 'metadata (title present)' (-not [string]::IsNullOrWhiteSpace($state.Title)) "'$($state.Title)'"
Check 'initial status is Playing' ($state.Status -eq 'Playing') "$($state.Status)"

# --- 3. Play/Pause key toggles ---
Press-MediaKey $VK_PLAYPAUSE; Start-Sleep 2
$paused = Get-State
Check 'media key pauses' ($paused.Status -eq 'Paused') "$($paused.Status)"

Press-MediaKey $VK_PLAYPAUSE; Start-Sleep 2
$resumed = Get-State
Check 'media key resumes' ($resumed.Status -eq 'Playing') "$($resumed.Status)"

# --- 4. Next / Previous ---
$before = (Get-State).Title
Press-MediaKey $VK_NEXT; Start-Sleep 3
$afterNext = Get-State
Check 'next key changes track' ($afterNext.Title -ne $before) "'$before' -> '$($afterNext.Title)'"

Press-MediaKey $VK_PREV; Start-Sleep 1; Press-MediaKey $VK_PREV; Start-Sleep 3
$afterPrev = Get-State
Check 'previous key returns' ($afterPrev.Title -eq $before) "'$($afterPrev.Title)'"

# --- Summary ---
$failed = @($results.Values | Where-Object { -not $_ }).Count
$passed = $results.Count - $failed
$color = if ($failed -eq 0) { 'Green' } else { 'Red' }
Write-Host ''
Write-Host ("{0}/{1} checks passed." -f $passed, $results.Count) -ForegroundColor $color
Write-Host 'Manual checks (flyout art, lock screen, seek bar): see TESTING.md'

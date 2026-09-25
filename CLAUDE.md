# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

PomoPulse - A Garmin Connect IQ application for Forerunner 255 that measures the
quality of deep work: it combines Flowtimer/Pomodoro timing with wrist sensing to
track depth (0-100, live), deep minutes, interruptions, and a per-session Deep Work
Quality score (0-100). See `docs/deep-work-model.md` for the model and rationale.

## Architecture

- **Language**: Monkey C (Garmin Connect IQ SDK)
- **Target Device**: Forerunner 255 series (fr255, fr255m, fr255s, fr255sm)
- **Display**: 260x260 round

## Key Files

- `source/PomoPulseApp.mc` - Main application entry point
- `source/PomoPulseView.mc` - Main timer UI (work/break/idle screens, live depth dots + unbroken counter, daily goal teaser)
- `source/PomoPulseDelegate.mc` - Button input handler for main view
- `source/TimerController.mc` - Work/break state machine with Pomodoro logic
- `source/DeepWorkEngine.mc` - Depth engine: continuity ramp, interruption detection (motion bursts, steps, self-logged), engagement (settledness + inverted-U arousal vs personal HR/HRV baseline), quality score, trend buffer
- `source/SensorManager.mc` - Sensor collection: 25 Hz accelerometer → per-second motion intensity, steps (ActivityMonitor), HR, beat intervals
- `source/HrvAnalyzer.mc` - RMSSD from beat intervals (ectopic filter with lock-out escape, freshness check)
- `source/SessionManager.mc` - FIT recording: per-second Depth + session Quality / Deep Minutes / Interruptions fields
- `source/HistoryManager.mc` - Session persistence + deep-time / quality / insight analytics (Storage API)
- `source/StatsView.mc` - Stats screen (UP button): 4 pages — Today / Week / Insights / Records
- `source/SessionSummaryView.mc` - Post-session summary (quality hero, sparkline, break-ins, you-vs-watch) + breakdown/coaching page; also `SelfRatingMenu`
- `source/CycleSummaryView.mc` - Pomodoro cycle summary (deep minutes, cycle quality)
- `source/SettingsView.mc` - Settings menu (mode, durations, deep goal, live depth toggle, Garmin sync, reset baseline, clear history)
- `tools/depth_model.py` - Desktop Python mirror of the engine for tuning thresholds against synthetic scenarios (keep in sync with DeepWorkEngine.mc)

## Deep Work Model

Depth is momentum: it builds with unbroken time and is knocked down by
interruptions. Physiology only modulates it.

- **Depth (0-100, per second)** = continuity ramp (0→100 over 8 unbroken min)
  × engagement / 100. Zones: Deep (>=70), Focused (40-69), Shallow (<40).
- **Interruptions**: motion burst (>=10 gross-motion seconds in 30 s) halves the
  ramp, escalating to a reset after 45 s; walking (>=15 steps in ~60 s) resets;
  DOWN during focus logs a distraction (halves). Resuming from a pause breaks the
  block (halve if <2 min, else reset) but isn't counted as an interruption.
- **Engagement** = 60% settledness (gross motion = 0; typing is fine; stillness
  + under-arousal = "drifting" 50) + 40% arousal, an inverted-U around the
  personal working baseline (RMSSD 70-120% or HR -3..+10 bpm = 100). Baselines
  (`hrvBaseline`, `hrBaseline` in Storage) are learned from settled seconds of
  saved sessions; uncalibrated arousal is a neutral 75.
- **Session Quality** = 55% deep-time ratio (80% deep → 100) + 20% continuity
  (longest block vs min(session, 25 min)) + 25% average engagement.
- After each saved session the user self-rates (Deep / Solid / Shallow) *before*
  seeing the score; Stats > Insights shows watch-vs-you agreement.
- History records add `quality`, `deepSec`, `intr`, `longest`, `ttd`, `eng`,
  `rating`. `avgFlowScore` now holds average depth. Sessions without `quality`
  are legacy (pre-engine) and are excluded from depth stats.
- Constants are first guesses; tune with `python3 tools/depth_model.py` and keep
  the model in sync.

Depth is recorded at app level via TimerController's record callback, so
recording continues while stats/settings views are open. Every way a session
ends goes through `PomoPulseApp.finishSession()`. Duration properties store
minutes (matching settings.xml); legacy seconds values are migrated on load.

## Environment Setup

The SDK tools require these on PATH before any build/run commands:

```bash
export PATH="$HOME/jre21/bin:$HOME/connectiq-sdk/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/libs:$LD_LIBRARY_PATH"
```

**libsecret workaround**: If the simulator fails with `undefined symbol: g_task_set_static_name`,
the custom `~/libs/libsecret-1.so.0` is overriding the system one. Fix once:
```bash
mv ~/libs/libsecret-1.so.0 ~/libs/libsecret-1.so.0.bak
```
The system libsecret (0.21.4) is sufficient.

## Build Commands

```bash
# Compile for FR255 (strict type checking)
monkeyc -d fr255 -f monkey.jungle -o bin/PomoPulse.prg -y ~/garmin-keys/developer.der -l 3 --warn

# Compile with relaxed type checking (for quick iteration)
monkeyc -d fr255 -f monkey.jungle -o bin/PomoPulse.prg -y ~/garmin-keys/developer.der -l 0

# Run in simulator (requires X11 / WSLg display)
connectiq &          # or: ~/.Garmin/ConnectIQ/AppImages/simulator-8.4.1.AppImage &
monkeydo bin/PomoPulse.prg fr255   # NOTE: blocks while app is running; use & to background

# Deploy to physical device (WSL2 — replace 'e' with actual drive letter)
cp bin/PomoPulse.prg /mnt/e/GARMIN/GARMIN/APPS/
```

### Deploy to physical FR255

The FR255 mounts as an MTP device (no drive letter) — copy via two steps from WSL2:

```bash
# Step 1: Stage the build on the Windows C drive
cp bin/PomoPulse.prg /mnt/c/Users/samit/PomoPulse.prg

# Step 2: Copy from C drive to watch via PowerShell MTP Shell.Application
powershell.exe -NoProfile -Command '
$shell  = New-Object -ComObject Shell.Application
$pc     = $shell.Namespace(0x11)
$device = $pc.Items() | Where-Object { $_.Name -like "*Forerunner*" }
$deviceNS = $shell.Namespace($device.Path)
$storage  = $deviceNS.Items() | Where-Object { $_.Name -like "*Internal*" }
$garmin   = $storage.GetFolder.Items() | Where-Object { $_.Name -eq "GARMIN" }
$apps     = $garmin.GetFolder.Items()  | Where-Object { $_.Name -eq "APPS" }
$apps.GetFolder.CopyHere("C:\Users\samit\PomoPulse.prg", 0x14)
Start-Sleep -Seconds 5
Write-Host "Done."
'
```

Prerequisites:
1. Connect watch via USB and select **File Transfer / Garmin** mode on the watch
2. Confirm the device appears as "Forerunner 255" under This PC in Windows Explorer

## Button Mapping (FR255)

- **START/STOP**: Toggle timer (start/pause)
- **BACK/LAP**: Reset timer or exit
- **UP (long)**: Open settings menu
- **UP (short)**: View stats
- **DOWN**: During focus: log a distraction ("I got pulled away"). During a Pomodoro break: skip the break

## UI Testing

Two scripts automate simulator testing on WSLg (requires `xdotool` and `grim`):

```bash
# Install once
sudo apt-get install -y grim

# Full UI walkthrough with screenshots (12 steps)
./ui-test.sh

# Structured test suite with PASS/FAIL tracking and HTML report
./tests/ui-suite.sh

# Save new baseline screenshots (after intentional UI changes)
./tests/ui-suite.sh --save-baseline
```

Note: after any intentional UI change, re-run with `--save-baseline` first —
the stored baselines are stale otherwise and every visual test will FAIL.

Screenshots use `grim` (Wayland compositor capture via `WAYLAND_DISPLAY=wayland-0`) — reads directly
from the Weston compositor framebuffer, unaffected by window z-order. Key injection uses Win32
`PostMessage(WM_KEYDOWN)` via `powershell.exe`, bypassing Wayland/X11 focus restrictions.

**Known limitation**: Long-press UP (settings menu) cannot be reliably triggered via synthetic
Win32 key events in the Garmin simulator — `onMenu` hold detection does not fire.

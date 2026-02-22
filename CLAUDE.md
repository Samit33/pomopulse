# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

PomoPulse - A Garmin Connect IQ application for Forerunner 255 that combines Pomodoro timing with multi-sensor biofeedback to calculate a "Flow Score" (0-100) representing focus quality.

## Architecture

- **Language**: Monkey C (Garmin Connect IQ SDK)
- **Target Device**: Forerunner 255 series (fr255, fr255m, fr255s, fr255sm)
- **Display**: 260x260 round

## Key Files

- `source/PomoPulseApp.mc` - Main application entry point
- `source/PomoPulseView.mc` - Main timer UI (work/break/idle screens, flow score display)
- `source/PomoPulseDelegate.mc` - Button input handler for main view
- `source/TimerController.mc` - Work/break state machine with Pomodoro logic
- `source/FlowScoreCalculator.mc` - Weighted algorithm combining HRV, HR stability, movement, stress, SpO2
- `source/SensorManager.mc` - Real-time sensor data collection (HR, accelerometer, SpO2)
- `source/HrvAnalyzer.mc` - RMSSD calculation from beat intervals
- `source/SessionManager.mc` - FIT recording with custom FlowScore field
- `source/HistoryManager.mc` - Session persistence using Storage API
- `source/StatsView.mc` - Historical stats screen (UP button)
- `source/SessionSummaryView.mc` - Post-session summary screen (avg/peak flow, zone %)
- `source/SettingsView.mc` - Settings menu (work/break durations, long break interval)

## Flow Score Algorithm

Weighted composite (0-100):
- HRV (RMSSD): 35% - Higher parasympathetic activity = better cognitive performance
- HR Stability: 20% - Low HR variance = sustained arousal
- Movement: 20% - Physical stillness indicates deep focus
- Stress (inverted): 20% - Lower Garmin stress = higher score
- SpO2: 5% - Minor factor, penalizes only if compromised

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
- **DOWN**: Skip current phase (work→break or break→work)

## UI Testing

Two scripts automate simulator testing on WSLg (requires `xdotool`):

```bash
# Full UI walkthrough with screenshots (12 steps)
./ui-test.sh

# Structured test suite with PASS/FAIL tracking and HTML report
./tests/ui-suite.sh

# Save new baseline screenshots (after intentional UI changes)
./tests/ui-suite.sh --save-baseline
```

Screenshots use PowerShell `CopyFromScreen` (not scrot) because WSLg renders via Windows RDP
and X11 tools only capture a black framebuffer.

**Known limitation**: Long-press UP (settings menu) cannot be reliably triggered via xdotool
in the Garmin simulator — `onMenu` hold detection does not fire from synthetic key events.

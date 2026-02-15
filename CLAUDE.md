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
- `source/TimerController.mc` - Work/break state machine with Pomodoro logic
- `source/FlowScoreCalculator.mc` - Weighted algorithm combining HRV, HR stability, movement, stress, SpO2
- `source/SensorManager.mc` - Real-time sensor data collection (HR, accelerometer, SpO2)
- `source/HrvAnalyzer.mc` - RMSSD calculation from beat intervals
- `source/SessionManager.mc` - FIT recording with custom FlowScore field
- `source/HistoryManager.mc` - Session persistence using Storage API

## Flow Score Algorithm

Weighted composite (0-100):
- HRV (RMSSD): 35% - Higher parasympathetic activity = better cognitive performance
- HR Stability: 20% - Low HR variance = sustained arousal
- Movement: 20% - Physical stillness indicates deep focus
- Stress (inverted): 20% - Lower Garmin stress = higher score
- SpO2: 5% - Minor factor, penalizes only if compromised

## Build Commands

```bash
# Compile for FR255
monkeyc -d fr255 -f monkey.jungle -o bin/PomoPulse.prg -y ~/garmin-keys/developer.der -l 3 --warn

# Run in simulator (requires X11)
connectiq &
monkeydo bin/PomoPulse.prg fr255

# Deploy to physical device
cp bin/PomoPulse.prg /media/$USER/GARMIN/GARMIN/APPS/
```

## Button Mapping (FR255)

- **START/STOP**: Toggle timer (start/pause)
- **BACK/LAP**: Reset timer or exit
- **UP (long)**: Open settings menu
- **UP (short)**: View stats
- **DOWN**: Skip current phase (work→break or break→work)

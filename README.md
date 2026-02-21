# PomoPulse

A Garmin Connect IQ application for the Forerunner 255 that combines Pomodoro timing with multi-sensor biofeedback to calculate a **Flow Score** (0–100) representing focus quality in real time.

## Features

- **Pomodoro Timer** — 25/5/15 min work/break/long-break cycles, fully configurable
- **Flow Score** — live composite score from heart rate variability, movement, stress, and SpO2
- **FIT Recording** — per-second Flow Score saved to Garmin Connect activity files
- **Session History** — up to 50 sessions stored locally with daily and all-time stats
- **Round display UI** — optimized for the 260×260 circular screen

## Flow Score Algorithm

Weighted composite (0–100):

| Sensor | Weight | Logic |
|--------|--------|-------|
| HRV (RMSSD) | 35% | Higher parasympathetic activity = better cognitive performance |
| HR Stability | 20% | Low heart rate variance = sustained arousal |
| Movement | 20% | Physical stillness indicates deep focus |
| Stress (inverted) | 20% | Lower Garmin stress score = higher Flow Score |
| SpO2 | 5% | Penalizes only if oxygen saturation is compromised |

## Requirements

- Garmin Forerunner 255 (fr255)
- [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/)
- Garmin developer key (`~/garmin-keys/developer.der`)
- Java 11+

## Setup

```bash
# Install the Connect IQ SDK
./setup-sdk.sh
```

## Build & Deploy

```bash
# Compile for FR255
./build.sh

# Run in simulator (requires X11)
connectiq &
monkeydo bin/PomoPulse.prg fr255

# Deploy to physical device
cp bin/PomoPulse.prg /media/$USER/GARMIN/GARMIN/APPS/
```

## Button Mapping

| Button | Action |
|--------|--------|
| START/STOP | Toggle timer (start / pause) |
| BACK/LAP | Reset timer or exit |
| UP (long press) | Open settings menu |
| UP (short press) | View session stats |
| DOWN | Skip current phase (work → break or break → work) |

## Project Structure

```
source/
├── PomoPulseApp.mc          # App entry point
├── PomoPulseView.mc         # Main UI (timer, flow score gauge)
├── PomoPulseDelegate.mc     # Button input handling
├── TimerController.mc       # Pomodoro state machine
├── FlowScoreCalculator.mc   # Weighted Flow Score algorithm
├── SensorManager.mc         # HR, HRV, SpO2, accelerometer, stress
├── HrvAnalyzer.mc           # RMSSD calculation from beat intervals
├── SessionManager.mc        # FIT recording with custom FlowScore field
├── HistoryManager.mc        # Session persistence via Storage API
├── StatsView.mc             # Statistics and session history UI
└── SettingsView.mc          # Settings menu
```

## Settings

Configurable via long-press UP on the watch:

- Work duration (10–60 min, default 25)
- Short break duration (1–30 min, default 5)
- Long break duration (5–60 min, default 15)
- Auto-start break after work session

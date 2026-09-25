# PomoPulse

A Garmin Connect IQ application for the Forerunner 255 that measures the **quality of deep work**: how long you stayed unbroken, how often you were pulled away, and how engaged you were, rolled up into deep minutes and a per-session **Deep Work Quality** score (0–100).

## Features

- **Flowtimer and Pomodoro modes**: open-ended sessions or fixed work/break cycles
- **Depth tracking**: depth builds with unbroken time and drops when you're interrupted (phone pickups, getting up, or distractions you log with DOWN)
- **Deep minutes and daily goal**: the number that matters, measured against a daily target (default 2 h)
- **Self-rating**: rate each session before you see the watch's score; the app tracks how often you and the watch agree
- **Insights**: your peak hours, best session length, and break-ins per hour
- **FIT recording**: per-second Depth, plus session Quality / Deep Minutes / Interruptions in Garmin Connect
- **Round display UI**: optimized for the 260×260 circular screen

## How depth is measured

```
depth      = continuity ramp (0→100 over 8 unbroken min) × engagement
engagement = 60% settledness (no gross motion; typing is fine)
           + 40% arousal (inverted-U around your personal HR/HRV baseline)
quality    = 55% deep-time ratio + 20% longest unbroken block + 25% engagement
```

See [docs/deep-work-model.md](docs/deep-work-model.md) for the reasoning, the
limits, and how to tune it with `python3 tools/depth_model.py`.

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
| DOWN | During focus: log a distraction · During a break: skip it |

## Project Structure

```
source/
├── PomoPulseApp.mc          # App entry point
├── PomoPulseView.mc         # Main UI (timer, live depth, daily goal)
├── PomoPulseDelegate.mc     # Button input handling
├── TimerController.mc       # Pomodoro state machine
├── DeepWorkEngine.mc        # Depth / interruptions / quality engine
├── SensorManager.mc         # 25 Hz motion, steps, HR, beat intervals
├── HrvAnalyzer.mc           # RMSSD calculation from beat intervals
├── SessionManager.mc        # FIT recording (Depth + session fields)
├── HistoryManager.mc        # Session persistence via Storage API
├── StatsView.mc             # Statistics and session history UI
└── SettingsView.mc          # Settings menu
```

## Settings

Configurable via long-press UP on the watch:

- Timer mode (Flowtimer / Pomodoro)
- Work / short break / long break durations (Pomodoro)
- Daily deep-work goal (60–240 min, default 120)
- Live depth indicator on/off
- Garmin Sync on/off
- Reset HR/HRV baseline, clear history

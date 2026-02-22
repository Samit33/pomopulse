# PomoPulse — Session Handoff Notes
_Last updated: 2026-02-21_

## What was done this session

1. **GitHub repo** — https://github.com/Samit33/pomopulse (pushed, public)
2. **README.md** — added full setup/build/deploy docs
3. **SDK toolchain installed** (no sudo) — fully working:
   - Compiler: `~/connectiq-sdk/bin/monkeyc` (SDK 8.4.1)
   - JRE: `~/jre21/bin/java`
   - Developer key: `~/garmin-keys/developer.der`
   - Device definitions + **fonts**: `~/.Garmin/ConnectIQ/Devices/fr255/` + `~/.Garmin/ConnectIQ/Fonts/`
   - Simulator: `~/.Garmin/ConnectIQ/AppImages/simulator-8.4.1.AppImage`
4. **Fixed simulator crashes**:
   - Font files were missing — re-downloaded with `--include-fonts` flag
   - `flowScore.format("%d")` → `.toString()` (type error)
   - Storage API can't serialize Symbol keys — changed all session dict keys from `:key` to `"key"` (SessionManager, HistoryManager, StatsView)
   - Eager screen dimension init in `PomoPulseView.initialize()`
5. **Fixed all strict type-checker errors** — build now passes `-l 3 --warn` cleanly (0 errors, 3 harmless warnings)
6. **Added `simulate.sh`** — one-shot build + launch + push script

All committed and pushed. Latest commit: `146057d`

---

## Pending tasks (pick up here next session)

### Task 2 — Deploy to physical Garmin FR255
- Build is ready: `bin/PomoPulse.prg`
- Plug watch in via USB, select "File Transfer / Garmin" mode on the watch
- FR255 will mount as a drive in Windows, accessible in WSL2 at `/mnt/<drive>/`
- Then run:
  ```bash
  cp bin/PomoPulse.prg "/mnt/<drive>/GARMIN/GARMIN/APPS/"
  ```
- Safely eject and check watch

### Task 3 — Test all button interactions in simulator
- Launch simulator: `./simulate.sh`
- Test each button via the simulator's input menu:
  - **START** — should start timer and begin ticking
  - **DOWN** — should skip work → break (or break → work)
  - **UP long press** — should open settings menu (Work Duration, Short Break, etc.)
  - **UP short press** — should push StatsView (shows session history)
  - **BACK** — should reset timer; if idle, exits app
- Document any crashes or rendering issues found

---

## Build commands cheatsheet

```bash
# Set up PATH for the session
export PATH="$HOME/jre21/bin:$HOME/connectiq-sdk/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/libs:$LD_LIBRARY_PATH"

# Strict build (use this going forward)
monkeyc -d fr255 -f monkey.jungle -o bin/PomoPulse.prg \
  -y ~/garmin-keys/developer.der -l 3 --warn

# Full simulate (build + launch simulator + push app)
./simulate.sh

# Push to already-running simulator
monkeydo bin/PomoPulse.prg fr255

# Deploy to physical watch (once mounted)
cp bin/PomoPulse.prg "/mnt/<drive>/GARMIN/GARMIN/APPS/"
```

## Font download command (if ever needed again for other devices)
```bash
LD_LIBRARY_PATH="$HOME/projects/pomopulse/squashfs-root/usr/lib:$HOME/libs" \
  /tmp/ciq-cli/connect-iq-sdk-manager device download -d <device-id> --include-fonts
```

## Key source files
| File | Purpose |
|---|---|
| `source/PomoPulseApp.mc` | App entry point, initializes all managers |
| `source/TimerController.mc` | Work/break state machine |
| `source/FlowScoreCalculator.mc` | Weighted HRV/HR/movement/stress/SpO2 algorithm |
| `source/SensorManager.mc` | Live sensor callbacks (HR, accel, SpO2, stress) |
| `source/HrvAnalyzer.mc` | RMSSD from beat intervals |
| `source/SessionManager.mc` | FIT recording with custom FlowScore field |
| `source/HistoryManager.mc` | Session persistence via Storage API |
| `source/PomoPulseView.mc` | Main watch face (timer + flow gauge) |
| `source/PomoPulseDelegate.mc` | Button handling |
| `source/StatsView.mc` | Session history display |
| `source/SettingsView.mc` | Settings menu (durations, auto-start) |

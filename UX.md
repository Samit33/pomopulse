# PomoPulse UX Interactions

FR255 physical buttons: START/STOP, BACK/LAP, UP, DOWN

---

## 1. Main Timer View (PomoPulseView)

The default screen. Shows a circular progress arc, countdown timer, HR readout, and pomodoro dot count.

### Display states

| State | Timer color | Label shown | Info shown |
|-------|-------------|-------------|------------|
| Idle | Gray arc | "Ready" | HR (bpm) |
| Work (running) | Blue arc | _(none)_ | HR (bpm) |
| Work (paused) | Gray arc | "Paused" | HR (bpm) |
| Break (paused) | Gray arc | "Short Break" or "Long Break" | "#N done - Rest up!", "Press START" hint |
| Break (running) | Teal arc | "Short Break" or "Long Break" | "#N done - Rest up!" |

### Button actions

| Button | Idle | Work (running) | Work (paused) | Break (paused) | Break (running) |
|--------|------|----------------|---------------|-----------------|-----------------|
| **START/STOP** | Start work timer + begin recording | Pause timer + pause recording | Resume timer + resume recording | Start break timer | Pause break timer |
| **BACK/LAP** | Exit app | Stop recording, show summary (if ≥30s), reset to idle | Stop recording, show summary (if ≥30s), reset to idle | Stop, reset to idle | Stop, reset to idle |
| **UP (short)** | Open Focus Stats | Open Focus Stats | Open Focus Stats | Open Focus Stats | Open Focus Stats |
| **UP (long)** | Open Settings | Open Settings | Open Settings | Open Settings | Open Settings |
| **DOWN** | _(no action)_ | _(no action)_ | _(no action)_ | _(no action)_ | _(no action)_ |

### Automatic transitions

- **Work timer reaches 0:00**: Vibrate, stop recording, show Session Summary (if >= 30s), then transition to break (paused). Pomodoro count increments. Every 4th pomodoro triggers a long break instead of short.
- **Break timer reaches 0:00**: Vibrate, reset to idle (work ready).

---

## 2. Focus Stats View (StatsView)

Opened via UP from main view. Three pages navigated with UP/DOWN; page dots at the bottom show position.

### Pages

- **Page 1 — Today**: total focus time (green, large), average flow score, Flow/Pomo mode breakdown, and the 3 most recent sessions (`F/P  HH:MM  flow-score  duration`, `+N more` if additional)
- **Page 2 — Week**: last-7-days focus bar chart (today highlighted teal), weekly total, day-of-week letters
- **Page 3 — Records**: current day streak, best day, best session flow score, total sessions, all-time focus

### Button actions

| Button | Action |
|--------|--------|
| **BACK/LAP** | Return to main timer view |
| **UP** | Previous page |
| **DOWN** | Next page |

---

## 3. Session Summary View (SessionSummaryView)

Shown automatically after a work session completes (natural completion or BACK reset, if >= 30s). Displayed as an overlay on top of main view.

### Display

**Page 1 — Flow overview:**
- Title: "Session Done" / "Pomodoro Done"
- Average flow score as hero number (colored by zone: teal >= 70, blue >= 40)
- Duration + peak score line
- Minute-by-minute flow sparkline with flow-threshold guide line
- Stacked zone bar (time in flow / focused / building)
- "First flow in N min" or "Flow zone not reached"
- Sessions with no HRV data show duration as hero and a watch-fit hint instead

**Page 2 — Signals (via DOWN/UP):**
- HRV Quality and Stillness with Low/Med/High ratings
- Best (longest) flow streak, time in flow %
- Baseline calibration status

### Button actions

| Button | Action |
|--------|--------|
| **START/STOP** | Dismiss, return to main view |
| **BACK/LAP** | Dismiss, return to main view |
| **UP** | Toggle overview/signals page |
| **DOWN** | Toggle overview/signals page |

---

## 4. Settings Menu (SettingsView)

Opened via long-press UP from main view. Standard Garmin Menu2.

### Menu items

| Item | Action |
|------|--------|
| Timer Mode | Flowtimer / Pomodoro picker |
| Work Duration | Opens duration picker (15-60 min) — Pomodoro mode only |
| Short Break | Opens duration picker (3-15 min) — Pomodoro mode only |
| Long Break | Opens duration picker (10-30 min) — Pomodoro mode only |
| Live Flow | Toggles the on-screen live flow-zone indicator (On/Off) |
| Reset Baseline | Shows "Reset HRV baseline?" confirmation — forgets learned HRV calibration |
| Clear History | Shows "Clear all history?" confirmation |

### Button actions

| Button | Action |
|--------|--------|
| **START/STOP** | Select highlighted item |
| **BACK/LAP** | Return to main view |
| **UP** | Navigate menu up |
| **DOWN** | Navigate menu down |

### Duration Picker (sub-menu)

| Button | Action |
|--------|--------|
| **START/STOP** | Select value, save, return to main view |
| **BACK/LAP** | Cancel, return to settings menu |
| **UP/DOWN** | Navigate options |

Current value is marked with "Current" subtitle.

### Clear History Confirmation

| Button | Action |
|--------|--------|
| **START/STOP** | Confirm — clears all session history |
| **BACK/LAP** | Cancel |

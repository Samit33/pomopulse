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

Opened via UP from main view. Shows today's total focus time, session count, and a scrollable list of individual sessions (start time + duration).

### Display

- Title: "Focus Stats"
- "Today" label with total focus time (green, large)
- Session count (dim)
- Divider line
- Scrollable session list: `#N  HH:MM  duration` per row (3 visible at a time)
- Arrow indicators when more sessions exist above/below
- Shows "No sessions today" if no sessions recorded today

### Button actions

| Button | Action |
|--------|--------|
| **BACK/LAP** | Return to main timer view |
| **UP** | Scroll session list up |
| **DOWN** | Scroll session list down |

---

## 3. Session Summary View (SessionSummaryView)

Shown automatically after a work session completes (natural completion or BACK reset, if >= 30s). Displayed as an overlay on top of main view.

### Display

- Title: "Session Done"
- Duration in minutes (large number)
- "min focus" label
- Three signal rows with Low/Med/High ratings (color-coded green/amber/red):
  - HRV Quality
  - Stillness
  - Recovery
- "Press any key" hint at bottom

### Button actions

| Button | Action |
|--------|--------|
| **START/STOP** | Dismiss, return to main view |
| **BACK/LAP** | Dismiss, return to main view |
| **UP** | Dismiss, return to main view |
| **DOWN** | Dismiss, return to main view |

---

## 4. Settings Menu (SettingsView)

Opened via long-press UP from main view. Standard Garmin Menu2.

### Menu items

| Item | Action |
|------|--------|
| Work Duration | Opens duration picker (15-60 min) |
| Short Break | Opens duration picker (3-15 min) |
| Long Break | Opens duration picker (10-30 min) |
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

# PomoPulse UX Interactions

FR255 physical buttons: START/STOP, BACK/LAP, UP, DOWN

The app is **dual-mode**: **Flowtimer** (default, open-ended) and **Pomodoro**
(fixed work/break cycles). Button behaviour on the main timer view depends on
the active mode. Mode is chosen in Settings and locked once a session starts.

---

## 1. Main Timer View (PomoPulseView)

The default screen. Shows a circular progress arc, timer, HR readout, and a
live flow-zone indicator (when enabled).

### Timer states

- **Flowtimer**: `IDLE` → `FLOW_RUNNING` ⇄ `FLOW_PAUSED`
- **Pomodoro**: `IDLE` → `POMO_WORK` → `POMO_BREAK_WAIT` → `POMO_BREAK`

### Button actions — Flowtimer

| Button | Idle | Running | Paused |
|--------|------|---------|--------|
| **START/STOP** | Start session + begin recording | Pause (active time freezes) | Resume |
| **BACK/LAP** | Exit app | Stop & save (see recording floor) | Stop & save |
| **UP (short)** | Open Focus Stats | Open Focus Stats | Open Focus Stats |
| **UP (long)** | Open Settings | Open Settings | Open Settings |
| **DOWN** | _(no action)_ | _(no action)_ | _(no action)_ |

### Button actions — Pomodoro

| Button | Idle | Work | Break wait | Break running |
|--------|------|------|------------|---------------|
| **START/STOP** | Start work + begin recording | _(no pausing in work)_ | Start break | Pause break |
| **BACK/LAP** | Exit app | "Abandon session?" confirmation | Skip break → next work | Skip break → next work |
| **UP (short)** | Open Focus Stats | Open Focus Stats | Open Focus Stats | Open Focus Stats |
| **UP (long)** | Open Settings | Open Settings | Open Settings | Open Settings |
| **DOWN** | _(no action)_ | _(no action)_ | Skip break → next work | Skip break → next work |

### Recording floor (both modes)

- Sessions with **≥ 10 minutes** of active focus are saved (FIT activity if
  Garmin Sync is on, plus local history) and the Session Summary is shown.
- Sessions **under 10 minutes** are discarded silently (a brief vibrate on a
  manual Flowtimer stop); nothing is recorded anywhere.

### Pomodoro abandon flow (BACK during work)

1. **"Abandon session?"** — NO keeps the timer running; YES continues:
2. If the abandoned work was **≥ 10 min**, **"Save as flow session?"** —
   YES converts it to a saved Flowtimer session (with summary); NO discards it.
   Under 10 min, it is discarded silently.

### Automatic transitions

- **Flowtimer**: soft **90-minute nudge** (single pulse); hard **120-minute
  ceiling** auto-stops and saves; **15-minute pause timeout** auto-stops and
  saves (both subject to the 10-min floor).
- **Pomodoro work reaches 0:00**: vibrate, stop, show Session Summary (if
  ≥ 10 min), advance to break wait. Sessions 1–3 → short break; session 4 →
  long break. Completing 4 work sessions shows the Cycle Summary.
- **Pomodoro break reaches 0:00**: vibrate, advance to next work.

---

## 2. Focus Stats View (StatsView)

Opened via **UP (short press)** from the main view. Three pages navigated with
UP/DOWN; page dots at the bottom show position.

### Pages

- **Page 1 — Today**: total focus time (large), average flow score, Flow/Pomo
  mode breakdown, and the most recent sessions.
- **Page 2 — Week**: last-7-days focus bar chart (today highlighted), weekly
  total, day-of-week letters.
- **Page 3 — Records**: current day streak, best day, best session flow score,
  total sessions, all-time focus.

| Button | Action |
|--------|--------|
| **BACK/LAP** | Return to main timer view |
| **UP** | Previous page |
| **DOWN** | Next page |

---

## 3. Session Summary View (SessionSummaryView)

Shown automatically after a saved session (natural completion, manual stop, or
converted abandon — all ≥ 10 min). Displayed as an overlay on the main view.

**Page 1 — Flow overview:**
- Title: "Session Done" / "Pomodoro Done"
- Average flow score as hero number (coloured by zone: teal ≥ 70, blue ≥ 40)
- Duration + peak score line
- Minute-by-minute flow sparkline with the flow-threshold guide line
- Stacked zone bar (time in flow / focused / building)
- "First flow in N min" or "Flow zone not reached"
- Sessions with no HRV data show duration as the hero plus a watch-fit hint

**Page 2 — Signals (via DOWN/UP):**
- HRV Quality and Stillness with Low/Med/High ratings
- Best (longest) flow streak, time in flow %
- Baseline calibration status

| Button | Action |
|--------|--------|
| **START/STOP** | Dismiss, return to main view |
| **BACK/LAP** | Dismiss, return to main view |
| **UP / DOWN** | Toggle overview / signals page |

---

## 4. Cycle Summary View (CycleSummaryView)

Shown after a full Pomodoro cycle (4 work sessions). Displays cycle focus time,
average flow across the cycle, and the number of cycles completed today.

| Button | Action |
|--------|--------|
| **START/STOP** or **BACK/LAP** | Dismiss, return to main view |

---

## 5. Settings Menu (SettingsView)

Opened via **long-press UP** from the main view. Standard Garmin Menu2.

| Item | Action |
|------|--------|
| Timer Mode | Flowtimer / Pomodoro picker |
| Work Duration | Duration picker (15–60 min) — Pomodoro mode only |
| Short Break | Duration picker (3–15 min) — Pomodoro mode only |
| Long Break | Duration picker (10–30 min) — Pomodoro mode only |
| Live Flow | Toggle the on-screen live flow-zone indicator (On/Off) |
| **Garmin Sync** | Toggle whether saved sessions are written as a FIT activity (On/Off) |
| Reset Baseline | "Reset HRV baseline?" confirmation — forgets learned HRV calibration |
| Clear History | "Clear all history?" confirmation |

### Garmin Sync (privacy)

- **On (default)**: a saved session is written as a FIT activity → syncs to
  Garmin Connect → onward to Strava (per your Garmin/Strava account settings).
- **Off**: no FIT activity is written; the session still appears in PomoPulse's
  own stats but never leaves the watch.
- Note: getting a session into Garmin Connect but not onto Strava's feed is a
  Strava-side choice (set default activity visibility to "Only You") — the
  Garmin→Strava bridge cannot filter by activity type.

### Button actions

| Button | Action |
|--------|--------|
| **START/STOP** | Select highlighted item / toggle |
| **BACK/LAP** | Return to main view |
| **UP / DOWN** | Navigate menu |

Duration pickers: START/STOP selects and saves, BACK cancels; the current value
is marked with a "Current" subtitle. Confirmations (Reset Baseline, Clear
History): START/STOP confirms, BACK cancels.

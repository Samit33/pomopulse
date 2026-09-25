# PomoPulse UX Interactions

FR255 physical buttons: START/STOP, BACK/LAP, UP, DOWN

The app is **dual-mode**: **Flowtimer** (default, open-ended) and **Pomodoro**
(fixed work/break cycles). Button behaviour on the main timer view depends on
the active mode. Mode is chosen in Settings and locked once a session starts.

---

## 1. Main Timer View (PomoPulseView)

The default screen. Shows a circular progress arc and the timer. During focus
it adds a live depth-zone indicator (shallow / focused / deep dots) and
"Nm unbroken", which reads "Interrupted" while a disruption is detected. Both
can be turned off with Live Depth. Idle screens show deep minutes today against
the daily goal, with a small progress bar.

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
| **DOWN** | _(no action)_ | Log a distraction (tick vibe) | _(no action)_ |

### Button actions — Pomodoro

| Button | Idle | Work | Break wait | Break running |
|--------|------|------|------------|---------------|
| **START/STOP** | Start work + begin recording | _(no pausing in work)_ | Start break | Pause break |
| **BACK/LAP** | Exit app | "Abandon session?" confirmation | Skip break → next work | Skip break → next work |
| **UP (short)** | Open Focus Stats | Open Focus Stats | Open Focus Stats | Open Focus Stats |
| **UP (long)** | Open Settings | Open Settings | Open Settings | Open Settings |
| **DOWN** | _(no action)_ | Log a distraction (tick vibe) | Skip break → next work | Skip break → next work |

### Recording floor (both modes)

- Sessions with **≥ 10 minutes** of active focus are saved (FIT activity if
  Garmin Sync is on, plus local history). You're asked "How deep was it?", then
  the Session Summary is shown.
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

Opened via **UP (short press)** from the main view. Four pages navigated with
UP/DOWN; page dots at the bottom show position.

### Pages

- **Page 1 — Today**: deep minutes vs daily goal (large), total focus, average
  quality and break-ins, and recent sessions (mode, start time, quality,
  deep/total minutes).
- **Page 2 — Week**: last-7-days stacked bars (full bar = focus time, bright
  part = deep time), weekly deep total.
- **Page 3 — Insights**: peak 2-hour window, best session length, break-ins
  per focused hour (7 days), and watch-vs-you rating agreement. Shows "--"
  until there's enough data.
- **Page 4 — Records**: current day streak, best deep day, best quality,
  longest unbroken block, all-time deep time.

| Button | Action |
|--------|--------|
| **BACK/LAP** | Return to main timer view |
| **UP** | Previous page |
| **DOWN** | Next page |

---

## 3. Self-Rating + Session Summary

After a saved session (natural completion, manual stop, auto-stop or converted
abandon, all ≥ 10 min), a **"How deep was it?"** menu appears first: Deep /
Solid / Shallow. BACK skips it. The rating is asked *before* the score is shown
so the watch's number can't anchor your answer.

**Summary page 1 — Overview:**
- Deep Work Quality as the hero number (teal ≥ 70, blue ≥ 40)
- "N deep min of M"
- Minute-by-minute depth sparkline with the deep threshold line
- Stacked zone bar (deep / focused / shallow)
- Break-ins and best unbroken block
- "Watch agrees: Deep" or "You Solid, watch Deep" when rated

**Summary page 2 — Breakdown (via DOWN/UP):**
- Deep time %, break-ins (and how many you tapped), longest block, time to
  deep, engagement (Low/Med/High, or Calibrating)
- One coaching tip picked from the session (e.g. "Put phone out of reach",
  "Try a startup ritual")

| Button | Action |
|--------|--------|
| **START/STOP** | Dismiss, return to main view |
| **BACK/LAP** | Dismiss, return to main view |
| **UP / DOWN** | Toggle overview / breakdown page |

---

## 4. Cycle Summary View (CycleSummaryView)

Shown after a full Pomodoro cycle (4 work sessions). Displays deep minutes
across the cycle, total focus minutes, cycle quality, and the number of cycles
completed today.

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
| Deep Goal | Daily deep-work goal picker (60–240 min, default 120) |
| Live Depth | Toggle the live depth dots and unbroken counter (On/Off) |
| **Garmin Sync** | Toggle whether saved sessions are written as a FIT activity (On/Off) |
| Reset Baseline | "Reset HR/HRV baseline?" confirmation — forgets learned HR/HRV calibration |
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

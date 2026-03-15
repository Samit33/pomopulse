# PomoPulse — Product Specification
**Version 1.0 | March 2026**
Target: Garmin Connect IQ | Device: Garmin Forerunner 255

---

## 1. Overview

PomoPulse is a Garmin Connect IQ application combining structured focus timing with biometric flow scoring. Flow quality is measured using HRV and movement data from the Forerunner 255.

The app has two modes. Both feed into a unified daily statistics view.

| | Pomodoro Mode | Flowtimer Mode |
|---|---|---|
| **Philosophy** | Structure. Discipline. Ritual. | Freedom. Trust. Flow. |
| **How it works** | Fixed-duration work/break cycles. Commit to the block or abandon it. No pausing. 4 sessions per cycle. | No predetermined duration. Start, focus, stop when ready. The session ends on your terms, not a timer's. |

**Default mode: Flowtimer.** The app opens in Flowtimer mode. Mode switch is accessible via a tab or toggle — not front-and-centre. Mode cannot be switched mid-session.

---

## 2. Shared Principles

### 2.1 Biometric Signals
Both modes use the same two inputs for flow scoring:
- HRV (Heart Rate Variability)
- Movement (accelerometer data)

SpO2 and HR Stability are excluded — unreliable as on-device signals.

If biometric data is unavailable during a session, the session still records normally. Flow score is shown as N/A.

### 2.2 Session Recording Floor
Any session under 10 minutes of active focus time is discarded with no record.

> When a session is discarded, display: *"Session too short to record (minimum 10 minutes)."*

### 2.3 Active Time Definition
Session duration = active, non-paused time only. Paused time is invisible in all stats and summaries.

### 2.4 Stats Are Focus-Only
Break time is never recorded or surfaced in any stats view. Only work/focus time counts toward daily totals.

### 2.5 Mode Switching
Users can switch modes freely between sessions. Once a session starts, the mode is locked until it ends.

---

## 3. Pomodoro Mode

### 3.1 Cycle Structure
- A Pomodoro cycle = 4 work sessions
- Sessions are labelled: Session 1 of 4, 2 of 4, 3 of 4, 4 of 4
- Sessions 1–3 are followed by a short break. Session 4 is followed by a long break
- Breaks are optional — the user can skip any break and go directly to the next work session
- A cycle is complete only when all 4 work sessions are finished
- Completed cycles accumulate through the day. A new cycle resets to Session 1 of 4

### 3.2 Work Session Behaviour
- **No pausing is allowed.** The session runs until the timer ends or the user abandons it
- Abandon requires a single confirmation prompt: *"Abandon this session?"* — no multi-step confirmation, no guilt language
- Default work session duration: **25 minutes** (user-configurable)

### 3.3 Break Behaviour
- Short break default: **5 minutes** (user-configurable)
- Long break default: **15–20 minutes** (user-configurable)
- Any break can be skipped with a single tap
- Breaks can be paused or extended freely — no penalty
- Break time is never recorded in stats

### 3.4 Abandoning a Session

| Elapsed Time | Behaviour |
|---|---|
| < 10 minutes | Silent discard. No record, no prompt. |
| ≥ 10 minutes | Offer the user a choice (see below) |

**When elapsed ≥ 10 minutes, offer two options:**
1. **Abandon entirely** — no record for this session
2. **Convert to Flowtimer session** — elapsed active time is recorded as a Flowtimer session; biometric data already collected carries over and generates a flow score

Rules for conversion:
- The offer applies to any session abandon with ≥10 min elapsed, not only the 4th session
- Converted sessions are tagged with a subtle "converted" indicator in the session log
- The Pomodoro cycle is marked incomplete if conversion happens
- Sessions completed before the abandoned one are already locked in as Pomodoro sessions and count toward daily totals regardless

### 3.5 Cycle Completion & Stats

After the 4th work session completes, display the cycle summary:

**Show:**
- Per-session flow scores (mini timeline, sessions 1–4)
- Cycle-level flow score (aggregate of all 4 sessions)
- Total focus minutes today (across both modes)
- Number of completed Pomodoro cycles today

**Never show:**
- Break duration
- Paused time
- Abandoned session data (unless converted)

---

## 4. Flowtimer Mode

### 4.1 Session Duration Rules

| Active Time | Behaviour |
|---|---|
| < 10 minutes | Discarded. Display: *"Session too short to record (minimum 10 minutes)."* |
| 10–25 minutes | Records. Labelled **"Short flow"** in session summary |
| 25–60 minutes | Records. Labelled **"Deep flow"** in session summary |
| 60–120 minutes | Records. Labelled **"Extended flow"** in session summary |
| > 120 minutes | Hard ceiling. Session auto-saves at 120 minutes (see Section 4.3) |

### 4.2 Pause Behaviour
- User can pause at any time
- Paused time does not count toward session duration
- If paused for more than **15 minutes**, session auto-ends:
  - If ≥10 min active time had been accumulated → session saves
  - If <10 min active time had been accumulated → session discards

### 4.3 Auto-Save Ceiling (Forgotten Session Protection)
- **At 90 minutes active:** gentle, non-intrusive nudge — *"Still in flow? Session will auto-save at 2 hours."* Informational only, not a demand to stop
- **At 120 minutes active:** hard auto-stop. Session saves immediately. Session summary displays. No confirmation prompt — asking defeats the purpose

### 4.4 Stopping a Session
- User taps Stop at any point
- If active time ≥ 10 minutes → session saves, summary screen displays
- If active time < 10 minutes → session discards, brief message shown
- No break screen follows a Flowtimer session

### 4.5 Session Summary
After a session saves, show:
- Session duration (active time only)
- Flow score
- Session label (Short / Deep / Extended flow)
- Today's aggregated stats: total focus minutes, number of sessions today, average flow score today

---

## 5. Daily Statistics View

Unified view accessible at any time, not just after a session.

### Show:
- Total focus minutes today (across both modes)
- Breakdown: X minutes from Pomodoro (N sessions) | Y minutes from Flowtimer (N sessions)
- Number of completed Pomodoro cycles today
- Chronological flow score trend across the day (all sessions, both modes)
- Session list: each session with mode, start time, duration, flow score

### Never show:
- Break time
- Paused time
- Discarded sessions (under 10 minutes)
- Abandoned Pomodoro sessions that were not converted

---

## 6. Edge Cases & Decision Log

Implement exactly as specified. These are not suggestions.

| Topic | Decision |
|---|---|
| Default mode | Flowtimer. App opens ready to start a Flowtimer session |
| Mode switch timing | Between sessions only. Mode is locked once a session starts |
| Abandoned session < 10 min | Silent discard. No record, no prompt |
| Abandoned session ≥ 10 min | Offer: abandon entirely OR convert to Flowtimer session |
| Conversion tagging | Converted sessions carry a subtle "converted" tag in the session log |
| Cycle completion gate | 4 completed work sessions. Skipped breaks do not affect completion |
| Pomodoro pause | Not allowed. Abandon is the only exit from an active work session |
| Break pause/extend | Allowed. Breaks can be paused or extended freely |
| Flowtimer pause timeout | 15 minutes. Auto-end after 15 min pause. Save if ≥10 min active, else discard |
| Flowtimer ceiling nudge | At 90 minutes active time. Informational only, no action required |
| Flowtimer auto-save | At 120 minutes. Hard stop, no confirmation prompt |
| Biometrics unavailable | Session records normally. Flow score shown as N/A |
| Break time in stats | Never recorded or shown. Focus time only |
| Paused time in stats | Never counted. Active time only |
| Flowtimer session labels | Short flow (10–25 min), Deep flow (25–60 min), Extended flow (60–120 min) |
| Stats atomic unit | Individual sessions. Pomodoro cycles are a grouping layer on top |

---

## 7. Required Screens

Build exactly these 6 screens. No more, no fewer.

| Screen | Applies To | Key Notes |
|---|---|---|
| Main Timer | Both modes | Start, active session, abandon/stop actions |
| Break Screen | Pomodoro only | Short / long break display with skip option |
| Session Summary | Both modes | Post-session stats and flow score |
| Cycle Summary | Pomodoro only | Shown after 4th session completes |
| Today's Stats | Both modes | Unified daily view, always accessible |
| Settings | Both modes | Configure session/break durations, default mode |

---

## 8. Out of Scope

Do not build any of the following in this version:

- SpO2 tracking or scoring
- HR Stability as a biometric signal
- Real-time flow score during a session (scores are post-session only)
- Social or sharing features
- Cloud sync
- Any screen beyond the 6 listed in Section 7

---

## 9. Open Questions for Builder

These require technical answers before implementation begins:

1. **Screen-on constraints** — can the app maintain screen state for a 2-hour Flowtimer session without the display sleeping on the FR255?
2. **Background activity model** — does the timer continue accurately if the user returns to the watch face mid-session?
3. **Data persistence** — where is session history stored on-device? What is the storage limit per app?
4. **HRV sampling frequency** — what rate is accessible via the Connect IQ API on the Forerunner 255?
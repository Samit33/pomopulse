# PomoPulse — UI/UX & Flow Score Overview

**Platform:** Garmin Forerunner 255 (260×260 round display, Monkey C / Connect IQ)
**Concept:** A Pomodoro timer that uses real-time biofeedback to score your focus quality (0–100) as you work.

---

## Screen Map

```
                    ┌─────────────────────┐
                    │   Main Timer Screen  │  ← Primary screen
                    └──────────┬──────────┘
           ┌────────────────┬──┴──┬──────────────────┐
           │                │     │                  │
        UP (short)    START/STOP  DOWN            BACK
           │            (toggle)  (skip)         (reset/exit)
           ▼
    ┌─────────────┐
    │ Stats Screen │
    └──────┬──────┘
           │ SELECT
           ▼
    ┌──────────────────┐
    │ Session List     │  (scrollable, UP/DOWN)
    └──────────────────┘

    UP (long press) from Main Timer
           ▼
    ┌──────────────────┐
    │ Settings Menu    │  Work Duration / Short Break /
    └──────────────────┘  Long Break / Auto-start / Clear History

    After a work session ends (timer reaches 0 or DOWN pressed)
           ▼
    ┌──────────────────┐
    │ Session Summary  │  (any button to dismiss → break starts)
    └──────────────────┘
```

---

## Screens in Detail

### 1. Main Timer Screen

The app's home. Adapts its look to the current phase.

```
        ●  ●  ●  ●          ← completed pomodoros (red dots, max 4 visible)
      ╭──────────╮
     ╱  25:00     ╲         ← countdown (large white digits)
    │     74       │        ← Flow Score (0–100, color-coded)
     ╲   Flow  ↑  ╱         ← zone label + trend arrow
      ╰──────────╯
         72 bpm              ← live heart rate
```

**Outer progress arc** — fills clockwise as the session progresses.
Color changes with context:

| Phase | Arc Color |
|---|---|
| Work — warming up | Muted blue |
| Work — running | Flow score color (red / orange / green) |
| Break | Teal |
| Paused / Idle | Gray |

**Flow Score color zones:**

| Score | Color | Label |
|---|---|---|
| 70–100 | Green | Flow |
| 40–69 | Orange | Focus |
| 0–39 | Red | Distracted |

**First 15 seconds:** "Calibrating…" + a small progress bar appear instead of the score while sensors settle.

**Trend arrow** (next to score): green ↑ when score is rising, red ↓ when falling, hidden when stable.

---

### 2. Stats Screen

Accessed: **UP (short press)** on the main screen.

```
        Focus Stats
        ───────────
  Today
   1:23  |  74           ← focus time | avg flow score (colored)
   3 sessions

  ─────────────────────

  All Time
  Total Focus    4:12
  Sessions          9
  Avg Flow         68
  Best Peak        91
```

- Press **SELECT** to drill into individual session history.
- Press **BACK** to return to the main screen.

---

### 3. Session List Screen

Accessed: **SELECT** on the Stats screen.

```
  Sessions
  ────────────────────────
  2/21   25:00    82     ← date | duration | avg flow (colored)
                 44% flow
  2/20   25:00    67
                 31% flow
  2/19   20:00    55
                 18% flow
         ▼
```

Scroll with **UP / DOWN**. **BACK** returns to Stats.

---

### 4. Session Summary Screen

Shown automatically when a work session ends.

```
  Session Done
  ────────────
       74            ← large avg flow score (colored)
     Avg Flow

  ─────────────────

  Duration     25:00
  Peak            91
  In Flow         42%

  Tip: Movement     ← weakest component (if avg < 70)

             Press any key
```

The "Tip" line calls out whichever sensor metric dragged the score down most (HRV, HR Stability, Movement, or Stress), giving the user an actionable hint.

Press any button to dismiss and start the break.

---

### 5. Settings Menu

Accessed: **UP (long press)** on the main screen.
Native Garmin Menu2 widget (scrollable list).

| Setting | Options |
|---|---|
| Work Duration | 15–60 min (5 min steps) |
| Short Break | 3, 5, 10, 15, 20, 25, 30 min |
| Long Break | 3, 5, 10, 15, 20, 25, 30 min |
| Auto-start Break | Toggle on/off |
| Clear History | Confirmation dialog |

---

## Button Map (any screen)

| Button | Main Timer | Stats | Session List | Summary | Settings |
|---|---|---|---|---|---|
| **START/STOP** | Toggle run/pause | — | — | Dismiss | — |
| **BACK** | Reset / exit app | → Main | → Stats | Dismiss | → Main |
| **UP (short)** | → Stats | — | Scroll up | Dismiss | — |
| **UP (long)** | → Settings | — | — | Dismiss | — |
| **DOWN** | Skip phase | — | Scroll down | Dismiss | — |

---

## How the Flow Score Works

The Flow Score is a **real-time 0–100 number** representing current focus quality. It combines five biometric signals, each scored 0–100, then merged with a weighted average and smoothed so it doesn't jump around.

### Signal Weights

| Signal | Weight | Why |
|---|---|---|
| HRV (RMSSD) | **35%** | Strongest validated predictor of cognitive performance — higher heart-rate variability = more parasympathetic (calm, focused) state |
| HR Stability | **20%** | Steady heart rate means sustained arousal without anxiety |
| Movement | **20%** | Physical stillness correlates with deep focus |
| Stress (Garmin) | **20%** | Garmin's own stress index (inverted — lower stress → higher score) |
| SpO2 | **5%** | Minor factor; only drags the score down if blood oxygen is compromised |

### Scoring Each Signal

```
HRV (RMSSD ms)
  ≤ 20 ms  →   0    (very low parasympathetic activity)
    100 ms  → 100    (high activity)
  Formula: (RMSSD − 20) × 1.25, clamped 0–100

HR Stability (std deviation in bpm)
  0 bpm std  → 100  (perfectly steady)
  ≥ 10 bpm   →   0  (erratic)
  Formula: 100 − (StdDev × 10), clamped 0–100

Movement (accelerometer magnitude in mg)
  ~1000 mg (resting, gravity only)  → 100
  Each +5 mg above resting          → −1 point
  Formula: 100 − ((Magnitude − 1000) / 5), clamped 0–100

Stress (Garmin index 0–100, lower = calmer)
  Stress = 0   → Score 100
  Stress = 50  → Score 50
  Formula: 100 − Stress; no data → 50 (neutral)

SpO2 (%)
  ≥ 95%  → 100  (healthy)
  85–95% → degrades linearly: (SpO2 − 85) × 10
  < 85%  →   0  (significant deficit)
  No data → 100 (don't penalize)
```

### Combining the Signals

```
RawScore = (HRV × 0.35) + (HR_Stability × 0.20)
         + (Movement × 0.20) + (Stress × 0.20) + (SpO2 × 0.05)
```

### Smoothing (Exponential Moving Average)

Raw sensor data is noisy. An EMA with α = 0.15 smooths it:

```
FlowScore = (0.15 × RawScore) + (0.85 × PreviousFlowScore)
```

This gives ~13 seconds of effective history — responsive to real changes but not twitchy.

### Trend Detection

Every second, the app compares the average of the last 5 scores against the 5 before that:

- Difference > +3 → improving (↑ shown in green)
- Difference < −3 → declining (↓ shown in red)
- Within ±3 → stable (no arrow)

### Warm-up

The first 15 seconds of every work session are a calibration window. Sensors stabilize, the UI shows "Calibrating…", and no statistics are recorded yet. After 15 seconds the live Flow Score appears.

---

## Color Palette Reference

| Element | Color |
|---|---|
| Background | Black |
| Flow zone (70–100) | Green `#44FF44` |
| Focus zone (40–69) | Orange `#FFAA00` |
| Distracted zone (0–39) | Red `#FF4444` |
| Work / running | Blue `#4488FF` |
| Break | Teal `#44DDAA` |
| Calibrating | Muted blue `#5566AA` |
| Titles / accent | Light blue `#44AAFF` |
| Primary text | White |
| Secondary text | Gray `#AAAAAA` |

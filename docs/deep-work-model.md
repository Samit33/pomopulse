# Measuring deep work on a wrist

## What was wrong with the Flow Score

The earlier Flow Score was 75% HRV (RMSSD) and 25% stillness, and it treated
*higher HRV = better focus*: an RMSSD 40% above your baseline scored 100.

That rewards the wrong thing. High RMSSD reflects parasympathetic dominance,
the physiology of rest. Demanding cognitive work generally *lowers* vagal
HRV a little. So the best way to max the old score was to relax, zone out or
doze. Research on flow and effort points to an inverted U: moderate
activation, not maximum calm.

Two other problems:

- **Stillness penalised typing.** Movement was accelerometer magnitude minus
  1 g, sampled at 1 Hz. Typing and writing lost points. Lifting a phone
  (which rotates the wrist but keeps |a| ≈ 1 g) barely registered.
- **Nothing measured interruptions.** Deep work (Newport) is concentration
  *without distraction*, and the thing that kills it is fragmentation: the
  phone check, getting up, switching tasks. The old score had no idea
  whether you'd been interrupted.

## The new model: depth is momentum

Deep work builds over minutes of unbroken attention, and interruptions
destroy it. After a break-in it takes time to get back in. So instead of
reading your body second by second, the engine tracks *momentum*:

```
depth       = continuityRamp × engagement / 100
ramp        : 0 → 100 over 8 unbroken minutes
engagement  = 60% settledness + 40% arousal
```

Continuity is built on the signals a wrist measures reliably:

| Event | How it's detected | Effect on the ramp |
|---|---|---|
| Motion burst (reaching for a phone, fidgeting) | ≥10 of the last 30 s had gross motion (25 Hz accel: vibration + wrist re-orientation) | halved; reset if it lasts 45 s |
| Got up / walked away | ≥15 steps in ~60 s (ActivityMonitor) | reset |
| Self-logged distraction | DOWN button during focus | halved |
| Pause (Flowtimer) | deliberate break, not counted as an interruption | halved if <2 min, else reset |

A quick glance at the watch (a few seconds of motion) does **not** count as
an interruption, and neither does typing.

**Engagement** adjusts depth; it can't create depth by itself:

- *Settledness*: gross motion scores 0, typing or stillness scores 100. Being
  motionless **and** under-aroused scores 50 ("drifting").
- *Arousal*: an inverted U around your personal working baseline.
  RMSSD at 70–120% of baseline (or HR −3…+10 bpm when HRV drops out) is the
  engaged band. Much higher (too relaxed or drowsy) or much lower (stressed)
  scores less. Baselines are learned from the settled parts of your saved
  sessions. Until they exist, arousal is a neutral 75.

## What the user sees

- **During focus**: three zone dots (shallow / focused / deep) and
  "Nm unbroken". No score to chase. The unbroken counter makes an
  interruption feel costly, which is the point.
- **After a session**: first you're asked *"How deep was it?"* (Deep / Solid
  / Shallow), **before** the watch shows its number, so the score can't
  anchor your answer. Then you see Deep Work Quality, deep minutes, the depth
  sparkline (build-ups and knock-downs), break-ins, longest block, and
  whether the watch agreed with you. The breakdown page gives one concrete
  coaching tip.
- **Stats**: today's deep minutes against a daily goal (default 2 h),
  a week chart of deep vs total focus time, and **Insights**:
  - *Peak hours*: the 2-hour window where your quality is highest
  - *Best length*: the session length that gives you the best quality
  - *Break-ins per focused hour* (7 days)
  - *Watch vs you*: how often the watch's verdict matched your rating
- **Garmin Connect**: per-second Depth chart, plus session-level Deep Work
  Quality, Deep Minutes and Interruptions in the activity summary.

## Session quality

```
quality = 55% deep-time ratio   (80% of the session deep → 100)
        + 20% continuity        (longest block ÷ min(session, 25 min))
        + 25% average engagement
```

The first minutes of any block can't be deep, so 100% deep time is
unreachable. Short sessions therefore top out lower. That's intended,
because depth compounds with time.

Synthetic check (`python3 tools/depth_model.py`):

| Scenario | Quality | Deep min |
|---|---|---|
| 50 min, uninterrupted | 99 | 44 |
| 25 min, uninterrupted | 97 | 19 |
| 10 min, uninterrupted | 74 | 4 |
| 25 min, 2 self-logged distractions | 74 | 15 |
| 25 min, walked away 3 min | 59 | 9 |
| 25 min, drowsy last 10 min | 64 | 9 |
| 25 min, phone check every 6 min | 28 | 0 |

## Honest limits

- A wrist can't tell deep reading from staring into space. The drift rule
  only catches stillness combined with low arousal. That gap is why the
  self-rating exists. Over time "Watch vs you" shows how far to trust the
  score for *your* kind of work.
- The motion and step thresholds are first estimates. Tune them against real
  sessions: change `DeepWorkEngine.mc` and `tools/depth_model.py` together.
- Wrist-optical beat intervals are noisy, so physiology gets the smallest
  weight, is smoothed, and only counts while fresh beats are arriving.

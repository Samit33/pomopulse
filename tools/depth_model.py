#!/usr/bin/env python3
"""Desktop model of source/DeepWorkEngine.mc for tuning without a watch.

Mirrors the Monkey C integer math line for line. When you change a constant
or rule in the engine, change it here too and re-run to see how the
synthetic scenarios move:

    python3 tools/depth_model.py

Scenarios are synthetic (random typing-level wrist motion plus scripted
events) - they check that the engine ranks sessions sensibly, not that the
absolute thresholds match a real wrist. Calibrate those against real
sessions and your own self-ratings (Stats > Insights > Watch vs you).
"""
import random

# ── Constants (keep in sync with DeepWorkEngine.mc) ─────────────────────
DEEP_THRESHOLD = 70
FOCUS_THRESHOLD = 40
RAMP_SECONDS = 480
GROSS_MOTION_MG = 150
STILL_MOTION_MG = 10
BURST_WINDOW = 30
BURST_ON = 10
BURST_OFF = 3
MAJOR_EPISODE_SECONDS = 45
STEP_SAMPLE_SECONDS = 5
STEP_RING_SIZE = 13
STEP_THRESHOLD = 15
ENGAGEMENT_ALPHA = 0.1


class Engine:
    def __init__(self, hrv_baseline=45.0, hr_baseline=68.0):
        self.hrv_baseline = hrv_baseline
        self.hr_baseline = hr_baseline
        self.elapsed = 0
        self.ramp = 0
        self.unbroken = 0
        self.longest_block = 0
        self.interruptions = 0
        self.manual = 0
        self.gross_ring = [0] * BURST_WINDOW
        self.gross_index = 0
        self.gross_count = 0
        self.step_ring = []
        self.walking = False
        self.in_episode = False
        self.episode_seconds = 0
        self.episode_major = False
        self.engagement_ema = 75.0
        self.engagement = 75
        self.engagement_sum = 0
        self.depth = 0
        self.deep_seconds = 0
        self.focus_seconds = 0
        self.time_to_deep = -1
        self.trend = []

    def arousal(self, rmssd, hrv_valid, hr):
        if hrv_valid and rmssd > 0 and self.hrv_baseline > 0:
            r = int(rmssd * 100.0 / self.hrv_baseline)
            if r < 50:
                return 30
            if r < 70:
                return 30 + (r - 50) * 7 // 2
            if r <= 120:
                return 100
            if r < 160:
                return 100 - (r - 120) * 7 // 4
            return 30
        if hr > 0 and self.hr_baseline > 0:
            d = hr - int(self.hr_baseline)
            if d < -10:
                return 30
            if d < -3:
                return 30 + (d + 10) * 10
            if d <= 10:
                return 100
            if d < 25:
                return 100 - (d - 10) * 14 // 3
            return 30
        return 75

    def _end_block(self):
        self.longest_block = max(self.longest_block, self.unbroken)
        self.unbroken = 0

    def _interrupt(self, major):
        self.interruptions += 1
        self._end_block()
        self.ramp = 0 if major else self.ramp // 2

    def log_distraction(self):
        self.manual += 1
        self._interrupt(False)

    def _update_walking(self, steps):
        if steps < 0 or self.elapsed % STEP_SAMPLE_SECONDS != 0:
            return
        self.step_ring.append(steps)
        if len(self.step_ring) > STEP_RING_SIZE:
            self.step_ring = self.step_ring[1:]
        delta = steps - self.step_ring[0]
        if delta < 0:
            self.step_ring = [steps]
            delta = 0
        self.walking = delta >= STEP_THRESHOLD

    def update(self, rmssd, hrv_valid, hr, motion, steps):
        self.elapsed += 1
        gross = 1 if motion >= GROSS_MOTION_MG else 0
        self.gross_count += gross - self.gross_ring[self.gross_index]
        self.gross_ring[self.gross_index] = gross
        self.gross_index = (self.gross_index + 1) % BURST_WINDOW
        self._update_walking(steps)

        if not self.in_episode:
            if self.gross_count >= BURST_ON or self.walking:
                self.in_episode = True
                self.episode_seconds = 0
                self.episode_major = self.walking
                self._interrupt(self.walking)
        else:
            self.episode_seconds += 1
            if not self.episode_major and (self.walking or self.episode_seconds >= MAJOR_EPISODE_SECONDS):
                self.episode_major = True
                self.ramp = 0
            if self.gross_count <= BURST_OFF and not self.walking:
                self.in_episode = False

        if not self.in_episode:
            self.ramp = min(self.ramp + 1, RAMP_SECONDS)
            self.unbroken += 1

        arousal = self.arousal(rmssd, hrv_valid, hr)
        if gross:
            settled = 0
        elif motion < STILL_MOTION_MG and arousal < 60:
            settled = 50
        else:
            settled = 100
        raw = settled * 0.6 + arousal * 0.4
        self.engagement_ema = ENGAGEMENT_ALPHA * raw + (1 - ENGAGEMENT_ALPHA) * self.engagement_ema
        self.engagement = max(0, min(100, int(self.engagement_ema)))
        self.engagement_sum += self.engagement

        self.depth = (self.ramp * 100 // RAMP_SECONDS) * self.engagement // 100
        if self.depth >= DEEP_THRESHOLD:
            self.deep_seconds += 1
            if self.time_to_deep < 0:
                self.time_to_deep = self.elapsed
        elif self.depth >= FOCUS_THRESHOLD:
            self.focus_seconds += 1

    def longest(self):
        return max(self.unbroken, self.longest_block)

    def quality(self):
        t = self.elapsed
        deep_ratio = min(100, self.deep_seconds * 125 // t)
        continuity = min(100, self.longest() * 100 // min(t, 1500))
        engagement = self.engagement_sum // t
        return (55 * deep_ratio + 20 * continuity + 25 * engagement) // 100


def simulate(minutes, events=(), rmssd=42.0, hr=72, seed=1):
    """events: (kind, start_minute, duration_seconds) with kind in
    phone | walk | doze | tap"""
    rng = random.Random(seed)
    engine = Engine()
    steps = 1000
    for t in range(minutes * 60):
        motion = rng.randint(5, 60)  # typing / writing jitter
        if rng.random() < 0.01:
            motion = rng.randint(150, 400)  # a glance at the watch, a sip
        r, h = rmssd + rng.uniform(-5, 5), hr
        for kind, start, dur in events:
            if start * 60 <= t < start * 60 + dur:
                if kind == "phone":
                    motion = rng.randint(80, 500)
                elif kind == "walk":
                    motion = rng.randint(200, 600)
                    steps += 2
                elif kind == "doze":
                    motion, r, h = 2, rmssd * 1.7, hr - 12
        engine.update(r, True, h, motion, steps)
        for kind, start, _ in events:
            if kind == "tap" and t == start * 60:
                engine.log_distraction()
    return engine


SCENARIOS = [
    ("25m clean", 25, []),
    ("50m clean", 50, []),
    ("10m clean", 10, []),
    ("50m, two 8s glances", 50, [("phone", m, 8) for m in (15, 35)]),
    ("25m, two self-logged distractions", 25, [("tap", 8, 1), ("tap", 16, 1)]),
    ("25m, walk away 3m at 12m", 25, [("walk", 12, 180)]),
    ("25m, phone check every 6m (40s)", 25, [("phone", m, 40) for m in (6, 12, 18, 24)]),
    ("25m, drowsy last 10m", 25, [("doze", 15, 600)]),
    ("90m, one walk at 45m", 90, [("walk", 45, 240)]),
]

if __name__ == "__main__":
    print(f"{'scenario':36s} {'quality':>7s} {'deep':>5s} {'breaks':>6s} {'longest':>7s} {'to deep':>7s}")
    for name, minutes, events in SCENARIOS:
        e = simulate(minutes, events)
        ttd = f"{e.time_to_deep // 60}m" if e.time_to_deep >= 0 else "never"
        print(f"{name:36s} {e.quality():7d} {e.deep_seconds // 60:4d}m {e.interruptions:6d} "
              f"{e.longest() // 60:6d}m {ttd:>7s}")

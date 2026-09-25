import Toybox.Application.Storage;
import Toybox.Lang;

//! Depth zones for live guidance and post-session breakdown
enum DepthZone {
    ZONE_WARMUP = 0,     // First minute — nothing lit yet
    ZONE_SHALLOW = 1,    // Depth < 40
    ZONE_FOCUSED = 2,    // Depth 40-69
    ZONE_DEEP = 3        // Depth >= 70
}

//! Measures the quality of deep work.
//!
//! Deep work is modelled as *momentum*, not as an instantaneous body
//! reading: depth builds up over minutes of unbroken concentration and is
//! knocked down by interruptions. The engine therefore rests on the most
//! reliable signals a wrist device has — continuity (interruptions detected
//! from gross motion and steps, plus self-logged distractions) — and uses
//! physiology only as a modulator:
//!
//!   depth = continuityRamp (0-100, full after RAMP_SECONDS unbroken)
//!           x engagement / 100
//!
//!   engagement = 60% settledness (no gross motion; typing is fine)
//!              + 40% arousal (inverted-U around your personal working
//!                HRV / HR baseline — too relaxed or too stressed both
//!                score lower)
//!
//! Interruptions:
//! - Motion burst (>= BURST_ON gross-motion seconds in the last 30 s):
//!   continuity ramp halves; if it lasts MAJOR_EPISODE_SECONDS it resets
//! - Walking (>= STEP_THRESHOLD steps in ~60 s): ramp resets (you got up)
//! - Self-logged distraction (DOWN button): ramp halves
//!
//! Session quality (0-100) = 55% deep-time ratio + 20% continuity
//! (longest unbroken block) + 25% average engagement.
class DeepWorkEngine {

    // Zone thresholds
    private const DEEP_THRESHOLD  = 70;
    private const FOCUS_THRESHOLD = 40;

    // Live indicator stays dark while sensors settle
    private const WARMUP_SECONDS = 60;

    // Unbroken seconds needed for the continuity ramp to reach 100.
    // With typical engagement this puts "deep" ~5-6 min into a clean block.
    private const RAMP_SECONDS = 480;

    // Motion classification (per-second motion intensity, milli-g)
    private const GROSS_MOTION_MG = 150;  // Reaching, lifting a phone, walking
    private const STILL_MOTION_MG = 10;   // Below typing / writing jitter

    // Motion-burst interruption detection over a sliding window
    private const BURST_WINDOW = 30;
    private const BURST_ON  = 10;   // Gross seconds in window to start an episode
    private const BURST_OFF = 3;    // Episode ends when gross seconds fall to this
    private const MAJOR_EPISODE_SECONDS = 45;

    // Walking detection: cumulative step samples every 5 s, ~60 s window
    private const STEP_SAMPLE_SECONDS = 5;
    private const STEP_RING_SIZE = 13;
    private const STEP_THRESHOLD = 15;

    // Pauses shorter than this halve the ramp; longer ones reset it
    private const SHORT_PAUSE_MS = 120000;

    // Engagement smoothing
    private const ENGAGEMENT_ALPHA = 0.1;

    // Trend buffer: one averaged depth point per minute, capped at 2h
    private const TREND_BUCKET_SECONDS = 60;
    private const MAX_TREND_POINTS = 120;

    // Personal baselines (typical working RMSSD / HR), learned across sessions
    private const HRV_BASELINE_KEY = "hrvBaseline";
    private const HR_BASELINE_KEY  = "hrBaseline";
    private const MIN_BASELINE_SAMPLES = 120;

    private var _hrvBaseline as Float = 0.0;
    private var _hrBaseline  as Float = 0.0;

    // ── Session state ─────────────────────────────────────────

    private var _elapsed as Number = 0;

    // Continuity
    private var _ramp          as Number = 0;
    private var _unbroken      as Number = 0;
    private var _longestBlock  as Number = 0;
    private var _interruptions as Number = 0;
    private var _manualDistractions as Number = 0;

    // Motion-burst window
    private var _grossRing  as Array<Number>;
    private var _grossIndex as Number = 0;
    private var _grossCount as Number = 0;

    // Step window
    private var _stepRing  as Array<Number>;
    private var _walking   as Boolean = false;

    // Current disruption episode
    private var _inEpisode      as Boolean = false;
    private var _episodeSeconds as Number = 0;
    private var _episodeMajor   as Boolean = false;

    // Engagement
    private var _engagementEma as Float = 75.0;
    private var _engagement    as Number = 75;
    private var _arousal       as Number = 75;
    private var _engagementSum as Number = 0;

    // Depth
    private var _depth      as Number = 0;
    private var _depthSum   as Number = 0;
    private var _deepSeconds  as Number = 0;
    private var _focusSeconds as Number = 0;
    private var _timeToDeep   as Number = -1;

    // Trend buffer
    private var _trend       as Array<Number>;
    private var _bucketSum   as Number = 0;
    private var _bucketCount as Number = 0;

    // Baseline learning accumulators (settled seconds only)
    private var _rmssdSum   as Float  = 0.0;
    private var _hrvSamples as Number = 0;
    private var _hrSum      as Number = 0;
    private var _hrSamples  as Number = 0;

    function initialize() {
        _grossRing = [] as Array<Number>;
        _stepRing  = [] as Array<Number>;
        _trend     = [] as Array<Number>;
        reset();
        _hrvBaseline = loadFloat(HRV_BASELINE_KEY);
        _hrBaseline  = loadFloat(HR_BASELINE_KEY);
    }

    private function loadFloat(key as String) as Float {
        try {
            var value = Storage.getValue(key);
            if (value instanceof Float) {
                return value as Float;
            } else if (value instanceof Number) {
                return (value as Number).toFloat();
            }
        } catch (ex) {
        }
        return 0.0;
    }

    // ── Per-second update ─────────────────────────────────────

    //! Feed one second of sensor data.
    //! motion: per-second motion intensity (mg), steps: cumulative daily
    //! steps (-1 if unavailable), hrvValid: beat intervals are fresh.
    function update(rmssd as Float, hrvValid as Boolean, heartRate as Number,
                    motion as Number, steps as Number) as Void {
        _elapsed++;

        // Gross-motion sliding window
        var gross = motion >= GROSS_MOTION_MG ? 1 : 0;
        _grossCount += gross - _grossRing[_grossIndex];
        _grossRing[_grossIndex] = gross;
        _grossIndex = (_grossIndex + 1) % BURST_WINDOW;

        updateWalking(steps);

        // Interruption episodes
        if (!_inEpisode) {
            if (_grossCount >= BURST_ON || _walking) {
                _inEpisode = true;
                _episodeSeconds = 0;
                _episodeMajor = _walking;
                interrupt(_walking);
            }
        } else {
            _episodeSeconds++;
            if (!_episodeMajor && (_walking || _episodeSeconds >= MAJOR_EPISODE_SECONDS)) {
                _episodeMajor = true;
                _ramp = 0;
            }
            if (_grossCount <= BURST_OFF && !_walking) {
                _inEpisode = false;
            }
        }

        if (!_inEpisode) {
            if (_ramp < RAMP_SECONDS) {
                _ramp++;
            }
            _unbroken++;
            learnBaselines(rmssd, hrvValid, heartRate);
        }

        // Engagement: settledness + arousal
        _arousal = calculateArousal(rmssd, hrvValid, heartRate);
        var settled;
        if (gross == 1) {
            settled = 0;
        } else if (motion < STILL_MOTION_MG && _arousal < 60) {
            // Motionless *and* under-aroused: drifting, not thinking
            settled = 50;
        } else {
            settled = 100;
        }
        var rawEngagement = (settled * 0.6) + (_arousal * 0.4);
        _engagementEma = (ENGAGEMENT_ALPHA * rawEngagement) +
                         ((1.0 - ENGAGEMENT_ALPHA) * _engagementEma);
        _engagement = clamp(_engagementEma.toNumber(), 0, 100);
        _engagementSum += _engagement;

        // Depth = continuity ramp gated by engagement
        _depth = (((_ramp * 100) / RAMP_SECONDS) * _engagement) / 100;
        _depthSum += _depth;

        if (_depth >= DEEP_THRESHOLD) {
            _deepSeconds++;
            if (_timeToDeep < 0) {
                _timeToDeep = _elapsed;
            }
        } else if (_depth >= FOCUS_THRESHOLD) {
            _focusSeconds++;
        }

        // Trend buffer
        _bucketSum += _depth;
        _bucketCount++;
        if (_bucketCount >= TREND_BUCKET_SECONDS && _trend.size() < MAX_TREND_POINTS) {
            _trend.add(_bucketSum / _bucketCount);
            _bucketSum = 0;
            _bucketCount = 0;
        }
    }

    //! Sample cumulative steps every few seconds; walking = enough steps
    //! across the ring (~1 minute)
    private function updateWalking(steps as Number) as Void {
        if (steps < 0 || (_elapsed % STEP_SAMPLE_SECONDS) != 0) {
            return;
        }
        _stepRing.add(steps);
        if (_stepRing.size() > STEP_RING_SIZE) {
            _stepRing = _stepRing.slice(1, null) as Array<Number>;
        }
        var delta = steps - _stepRing[0];
        // Daily step counter rolls over at midnight
        if (delta < 0) {
            _stepRing = [steps] as Array<Number>;
            delta = 0;
        }
        _walking = delta >= STEP_THRESHOLD;
    }

    //! Break the current block. Major interruptions reset the continuity
    //! ramp; minor ones halve it.
    private function interrupt(major as Boolean) as Void {
        _interruptions++;
        endBlock();
        _ramp = major ? 0 : _ramp / 2;
    }

    private function endBlock() as Void {
        if (_unbroken > _longestBlock) {
            _longestBlock = _unbroken;
        }
        _unbroken = 0;
    }

    //! User pressed DOWN: "I just got distracted"
    function logDistraction() as Void {
        _manualDistractions++;
        interrupt(false);
    }

    //! Resuming from a (Flowtimer) pause breaks the block but is a
    //! deliberate break, so it is not counted as an interruption.
    function onResume(pausedMs as Number) as Void {
        endBlock();
        _ramp = pausedMs < SHORT_PAUSE_MS ? _ramp / 2 : 0;
    }

    //! Inverted-U arousal score around the personal working baseline.
    //! RMSSD 70-120% of baseline (or HR within -3..+10 bpm) is the engaged
    //! band; far above (relaxed / drowsy) or far below (stressed) scores less.
    private function calculateArousal(rmssd as Float, hrvValid as Boolean,
                                      heartRate as Number) as Number {
        if (hrvValid && rmssd > 0.0 && _hrvBaseline > 0.0) {
            var r = ((rmssd * 100.0) / _hrvBaseline).toNumber();
            if (r < 50)   { return 30; }
            if (r < 70)   { return 30 + (((r - 50) * 7) / 2); }
            if (r <= 120) { return 100; }
            if (r < 160)  { return 100 - (((r - 120) * 7) / 4); }
            return 30;
        }
        if (heartRate > 0 && _hrBaseline > 0.0) {
            var d = heartRate - _hrBaseline.toNumber();
            if (d < -10) { return 30; }
            if (d < -3)  { return 30 + ((d + 10) * 10); }
            if (d <= 10) { return 100; }
            if (d < 25)  { return 100 - (((d - 10) * 14) / 3); }
            return 30;
        }
        // Not calibrated yet: neutral, so physiology neither helps nor hurts
        return 75;
    }

    private function learnBaselines(rmssd as Float, hrvValid as Boolean,
                                    heartRate as Number) as Void {
        if (hrvValid && rmssd > 0.0) {
            _rmssdSum += rmssd;
            _hrvSamples++;
        }
        if (heartRate > 0) {
            _hrSum += heartRate;
            _hrSamples++;
        }
    }

    private function clamp(value as Number, min as Number, max as Number) as Number {
        if (value < min) { return min; }
        if (value > max) { return max; }
        return value;
    }

    // ── Session end ───────────────────────────────────────────

    //! Fold this session's settled physiology into the personal baselines.
    //! Call once when a session is saved.
    function finalizeSession() as Void {
        if (_hrvSamples >= MIN_BASELINE_SAMPLES) {
            _hrvBaseline = blend(_hrvBaseline, _rmssdSum / _hrvSamples);
            store(HRV_BASELINE_KEY, _hrvBaseline);
        }
        if (_hrSamples >= MIN_BASELINE_SAMPLES) {
            _hrBaseline = blend(_hrBaseline, _hrSum.toFloat() / _hrSamples);
            store(HR_BASELINE_KEY, _hrBaseline);
        }
    }

    private function blend(baseline as Float, sessionAvg as Float) as Float {
        if (baseline <= 0.0) {
            return sessionAvg;
        }
        return (0.7 * baseline) + (0.3 * sessionAvg);
    }

    private function store(key as String, value as Float) as Void {
        try {
            Storage.setValue(key, value);
        } catch (ex) {
            // Non-fatal: baseline just won't persist this time
        }
    }

    //! Forget learned baselines (Settings > Reset Baseline)
    function resetBaseline() as Void {
        _hrvBaseline = 0.0;
        _hrBaseline  = 0.0;
        try {
            Storage.deleteValue(HRV_BASELINE_KEY);
            Storage.deleteValue(HR_BASELINE_KEY);
        } catch (ex) {
        }
    }

    // ── Getters ───────────────────────────────────────────────

    function isCalibrated() as Boolean {
        return _hrvBaseline > 0.0 || _hrBaseline > 0.0;
    }

    //! Whether any sensor data arrived this session
    function hasData() as Boolean {
        return _elapsed > 0;
    }

    //! Whether heart data (for the engagement component) arrived
    function hasPhysiology() as Boolean {
        return _hrvSamples > 0 || _hrSamples > 0;
    }

    function getCurrentZone() as DepthZone {
        if (_elapsed <= WARMUP_SECONDS) {
            return ZONE_WARMUP;
        }
        if (_depth >= DEEP_THRESHOLD) {
            return ZONE_DEEP;
        }
        if (_depth >= FOCUS_THRESHOLD) {
            return ZONE_FOCUSED;
        }
        return ZONE_SHALLOW;
    }

    //! Live depth (0-100) — recorded to the FIT file every second
    function getDepth() as Number {
        return _depth;
    }

    //! Seconds since the last interruption / pause
    function getUnbrokenSeconds() as Number {
        return _inEpisode ? 0 : _unbroken;
    }

    function isInterrupted() as Boolean {
        return _inEpisode;
    }

    function getInterruptions() as Number {
        return _interruptions;
    }

    function getManualDistractions() as Number {
        return _manualDistractions;
    }

    function getTrackedSeconds() as Number {
        return _elapsed;
    }

    function getDeepSeconds() as Number {
        return _deepSeconds;
    }

    function getDeepPercent() as Number {
        return _elapsed == 0 ? 0 : (_deepSeconds * 100) / _elapsed;
    }

    function getFocusPercent() as Number {
        return _elapsed == 0 ? 0 : (_focusSeconds * 100) / _elapsed;
    }

    //! Longest unbroken block, including the one still running
    function getLongestBlock() as Number {
        return _unbroken > _longestBlock ? _unbroken : _longestBlock;
    }

    //! Seconds from start until depth first reached the deep zone (-1 = never)
    function getTimeToDeep() as Number {
        return _timeToDeep;
    }

    function getAvgEngagement() as Number {
        return _elapsed == 0 ? 0 : _engagementSum / _elapsed;
    }

    function getAvgDepth() as Number {
        return _elapsed == 0 ? 0 : _depthSum / _elapsed;
    }

    //! Session deep-work quality (0-100)
    function getQuality() as Number {
        if (_elapsed == 0) {
            return 0;
        }
        // Deep-time ratio: 80% deep maps to 100 (the settle-in minutes of
        // any block can never be deep, so 100% is unreachable)
        var deepRatio = (_deepSeconds * 125) / _elapsed;
        if (deepRatio > 100) { deepRatio = 100; }

        // Continuity: longest block vs. the session (capped at 25 min, so a
        // 90-min session with one planned break isn't penalised)
        var span = _elapsed < 1500 ? _elapsed : 1500;
        var continuity = (getLongestBlock() * 100) / span;
        if (continuity > 100) { continuity = 100; }

        return ((55 * deepRatio) + (20 * continuity) + (25 * getAvgEngagement())) / 100;
    }

    //! Averaged depth per minute for the post-session sparkline
    function getTrend() as Array<Number> {
        return _trend;
    }

    //! Fields persisted with the session in history
    function getSessionRecord() as Dictionary {
        return {
            "quality"  => getQuality(),
            "deepSec"  => _deepSeconds,
            "intr"     => _interruptions,
            "longest"  => getLongestBlock(),
            "ttd"      => _timeToDeep,
            "eng"      => getAvgEngagement()
        } as Dictionary;
    }

    //! Reset for a new session (baselines are kept)
    function reset() as Void {
        _elapsed = 0;
        _ramp = 0;
        _unbroken = 0;
        _longestBlock = 0;
        _interruptions = 0;
        _manualDistractions = 0;

        _grossRing = [] as Array<Number>;
        for (var i = 0; i < BURST_WINDOW; i++) {
            _grossRing.add(0);
        }
        _grossIndex = 0;
        _grossCount = 0;

        _stepRing = [] as Array<Number>;
        _walking = false;

        _inEpisode = false;
        _episodeSeconds = 0;
        _episodeMajor = false;

        _engagementEma = 75.0;
        _engagement = 75;
        _arousal = 75;
        _engagementSum = 0;

        _depth = 0;
        _depthSum = 0;
        _deepSeconds = 0;
        _focusSeconds = 0;
        _timeToDeep = -1;

        _trend = [] as Array<Number>;
        _bucketSum = 0;
        _bucketCount = 0;

        _rmssdSum = 0.0;
        _hrvSamples = 0;
        _hrSum = 0;
        _hrSamples = 0;
    }
}

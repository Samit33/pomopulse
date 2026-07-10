import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Math;

//! Flow zones for live guidance and post-session breakdown
enum FlowZone {
    ZONE_WARMUP = 0,     // First minute — sensors settling, not judged
    ZONE_BUILDING = 1,   // Score < 40
    ZONE_FOCUSED = 2,    // Score 40-69
    ZONE_FLOW = 3        // Score >= 70
}

//! Calculates the Flow Score (0-100) from biofeedback signals.
//!
//! Two-signal composite:
//! - HRV (RMSSD): 75% - Strongest predictor of cognitive performance
//! - Movement:    25% - Physical stillness indicates deep focus
//!
//! HRV is scored against a personal baseline (learned across sessions and
//! persisted in Storage) so the score adapts to the wearer instead of using
//! a one-size-fits-all RMSSD band. When no beat intervals are arriving the
//! last HRV score is held rather than collapsing to zero.
class FlowScoreCalculator {

    // Weights (must sum to 1.0)
    private const WEIGHT_HRV      = 0.75;
    private const WEIGHT_MOVEMENT = 0.25;

    // Zone thresholds
    private const FLOW_THRESHOLD  = 70;
    private const FOCUS_THRESHOLD = 40;

    // Sensors need to settle before scores are trustworthy
    private const WARMUP_SECONDS = 60;

    // Flow must be sustained this long before it counts as "entered flow"
    private const FLOW_CONFIRM_SECONDS = 60;

    // Trend buffer: one averaged point per bucket, capped at 2h of data
    private const TREND_BUCKET_SECONDS = 60;
    private const MAX_TREND_POINTS = 120;

    // Personal baseline persistence
    private const BASELINE_STORAGE_KEY = "hrvBaseline";
    private const MIN_BASELINE_SAMPLES = 120;  // 2 min of valid HRV per session

    // Current component scores (0-100)
    private var _hrvScore      as Number = 50;
    private var _movementScore as Number = 50;

    // Smoothing: exponential moving average
    private const EMA_ALPHA = 0.15;  // ~13 s effective window
    private var _emaScore       as Float   = 50.0;
    private var _emaInitialized as Boolean = false;

    // Computed flow score
    private var _flowScore as Number = 50;

    // Elapsed sample time (seconds, 1 sample = 1 second)
    private var _elapsedSeconds as Number = 0;

    // Session aggregates (post-warmup only)
    private var _scoreSum   as Number = 0;
    private var _scoreCount as Number = 0;
    private var _peakScore  as Number = 0;
    private var _minScore   as Number = 100;

    // Time-in-zone tracking (seconds spent in each zone, post-warmup)
    private var _timeInFlow       as Number = 0;
    private var _timeInFocus      as Number = 0;
    private var _timeInDistracted as Number = 0;

    // Flow streak tracking
    private var _currentFlowStreak as Number = 0;
    private var _longestFlowStreak as Number = 0;
    private var _timeToFlow        as Number = -1;  // Seconds until flow confirmed, -1 = never

    // Trend buffer (averaged score per bucket)
    private var _trend       as Array<Number>;
    private var _bucketSum   as Number = 0;
    private var _bucketCount as Number = 0;

    // Personal HRV baseline (ms RMSSD); 0.0 = not calibrated yet
    private var _baselineRmssd as Float = 0.0;

    // Session RMSSD accumulation for baseline learning
    private var _rmssdSum       as Float  = 0.0;
    private var _hrvSampleCount as Number = 0;

    //! Constructor
    function initialize() {
        _trend = [] as Array<Number>;
        loadBaseline();
    }

    private function loadBaseline() as Void {
        try {
            var value = Storage.getValue(BASELINE_STORAGE_KEY);
            if (value != null && value instanceof Float) {
                _baselineRmssd = value as Float;
            } else if (value != null && value instanceof Number) {
                _baselineRmssd = (value as Number).toFloat();
            }
        } catch (ex) {
            _baselineRmssd = 0.0;
        }
    }

    //! Update sensor data and recalculate scores.
    //! hrvValid indicates whether beat intervals are currently flowing;
    //! when false the last HRV score is held instead of collapsing to 0.
    function updateSensorData(rmssd as Float, accelMagnitude as Number, hrvValid as Boolean) as Void {
        _movementScore = calculateMovementScore(accelMagnitude);

        if (hrvValid && rmssd > 0.0) {
            _hrvScore = calculateHrvScore(rmssd);
            _rmssdSum += rmssd;
            _hrvSampleCount++;
        }
        // else: hold previous _hrvScore (sensor dropout, not a real signal)

        // Weighted composite
        var rawScore = (_hrvScore * WEIGHT_HRV) +
                       (_movementScore * WEIGHT_MOVEMENT);

        var rawInt = rawScore.toNumber();

        // Apply EMA smoothing
        if (!_emaInitialized) {
            _emaScore = rawInt.toFloat();
            _emaInitialized = true;
        } else {
            _emaScore = (EMA_ALPHA * rawInt) + ((1.0 - EMA_ALPHA) * _emaScore);
        }

        _flowScore = _emaScore.toNumber();
        if (_flowScore < 0)   { _flowScore = 0; }
        if (_flowScore > 100) { _flowScore = 100; }

        _elapsedSeconds++;

        // Don't judge the warm-up minute — sensors are still settling
        if (_elapsedSeconds <= WARMUP_SECONDS) {
            return;
        }

        // Session aggregates
        _scoreSum += _flowScore;
        _scoreCount++;
        if (_flowScore > _peakScore) { _peakScore = _flowScore; }
        if (_flowScore < _minScore)  { _minScore  = _flowScore; }

        // Time in zones
        if (_flowScore >= FLOW_THRESHOLD) {
            _timeInFlow++;
        } else if (_flowScore >= FOCUS_THRESHOLD) {
            _timeInFocus++;
        } else {
            _timeInDistracted++;
        }

        // Flow streaks + time-to-flow
        if (_flowScore >= FLOW_THRESHOLD) {
            _currentFlowStreak++;
            if (_currentFlowStreak > _longestFlowStreak) {
                _longestFlowStreak = _currentFlowStreak;
            }
            if (_timeToFlow < 0 && _currentFlowStreak >= FLOW_CONFIRM_SECONDS) {
                _timeToFlow = _elapsedSeconds - FLOW_CONFIRM_SECONDS;
            }
        } else {
            _currentFlowStreak = 0;
        }

        // Trend buffer
        _bucketSum += _flowScore;
        _bucketCount++;
        if (_bucketCount >= TREND_BUCKET_SECONDS && _trend.size() < MAX_TREND_POINTS) {
            _trend.add(_bucketSum / _bucketCount);
            _bucketSum = 0;
            _bucketCount = 0;
        }
    }

    //! HRV score. With a personal baseline: 0.6x baseline = 0, 1.4x = 100.
    //! Without calibration: absolute band, RMSSD 20ms = 0, 100ms = 100.
    private function calculateHrvScore(rmssd as Float) as Number {
        var score;
        if (_baselineRmssd > 0.0) {
            score = (((rmssd / _baselineRmssd) - 0.6) * 125.0).toNumber();
        } else {
            score = ((rmssd - 20.0) * 1.25).toNumber();
        }
        return clamp(score, 0, 100);
    }

    //! Movement score: ~1000mg at rest (gravity), higher = more movement
    private function calculateMovementScore(accelMagnitude as Number) as Number {
        var excess = accelMagnitude - 1000;
        if (excess < 0) {
            excess = 0;
        }
        var score = (100 - (excess / 5)).toNumber();
        return clamp(score, 0, 100);
    }

    private function clamp(value as Number, min as Number, max as Number) as Number {
        if (value < min) { return min; }
        if (value > max) { return max; }
        return value;
    }

    //! Fold this session's average RMSSD into the personal baseline.
    //! Call once when a session is saved.
    function finalizeSession() as Void {
        if (_hrvSampleCount < MIN_BASELINE_SAMPLES) {
            return;
        }
        var sessionAvg = _rmssdSum / _hrvSampleCount;
        if (_baselineRmssd <= 0.0) {
            _baselineRmssd = sessionAvg;
        } else {
            _baselineRmssd = (0.7 * _baselineRmssd) + (0.3 * sessionAvg);
        }
        try {
            Storage.setValue(BASELINE_STORAGE_KEY, _baselineRmssd);
        } catch (ex) {
            // Non-fatal: baseline just won't persist this time
        }
    }

    //! Forget the learned personal baseline (Settings > Reset HRV Baseline)
    function resetBaseline() as Void {
        _baselineRmssd = 0.0;
        try {
            Storage.deleteValue(BASELINE_STORAGE_KEY);
        } catch (ex) {
        }
    }

    function isCalibrated() as Boolean {
        return _baselineRmssd > 0.0;
    }

    //! Whether real HRV data has been received this session
    function hasBiometrics() as Boolean {
        return _hrvSampleCount > 0;
    }

    //! Current zone for live guidance
    function getCurrentZone() as FlowZone {
        if (_elapsedSeconds <= WARMUP_SECONDS) {
            return ZONE_WARMUP;
        }
        if (_flowScore >= FLOW_THRESHOLD) {
            return ZONE_FLOW;
        }
        if (_flowScore >= FOCUS_THRESHOLD) {
            return ZONE_FOCUSED;
        }
        return ZONE_BUILDING;
    }

    function getFlowScore() as Number {
        return _flowScore;
    }

    function getHrvScore() as Number {
        return _hrvScore;
    }

    function getMovementScore() as Number {
        return _movementScore;
    }

    //! Session average score (post-warmup)
    function getAvgScore() as Number {
        if (_scoreCount == 0) {
            return 0;
        }
        return _scoreSum / _scoreCount;
    }

    function getPeakScore() as Number {
        return _peakScore;
    }

    function getMinScore() as Number {
        return _minScore;
    }

    function getTimeInFlow() as Number {
        return _timeInFlow;
    }

    function getTimeInFocus() as Number {
        return _timeInFocus;
    }

    function getTimeInDistracted() as Number {
        return _timeInDistracted;
    }

    function getTotalTrackedTime() as Number {
        return _timeInFlow + _timeInFocus + _timeInDistracted;
    }

    function getFlowZonePercent() as Number {
        var total = getTotalTrackedTime();
        if (total == 0) {
            return 0;
        }
        return (_timeInFlow * 100) / total;
    }

    function getFocusZonePercent() as Number {
        var total = getTotalTrackedTime();
        if (total == 0) {
            return 0;
        }
        return (_timeInFocus * 100) / total;
    }

    //! Seconds from session start until flow was first sustained (-1 = never)
    function getTimeToFlow() as Number {
        return _timeToFlow;
    }

    //! Longest unbroken run of flow-zone seconds
    function getLongestFlowStreak() as Number {
        return _longestFlowStreak;
    }

    //! Averaged score per minute for the session sparkline
    function getTrend() as Array<Number> {
        return _trend;
    }

    //! Reset calculator state for a new session (baseline is kept)
    function reset() as Void {
        _hrvScore      = 50;
        _movementScore = 50;
        _flowScore     = 50;
        _emaScore      = 50.0;
        _emaInitialized = false;
        _elapsedSeconds = 0;
        _scoreSum      = 0;
        _scoreCount    = 0;
        _peakScore     = 0;
        _minScore      = 100;
        _timeInFlow    = 0;
        _timeInFocus   = 0;
        _timeInDistracted = 0;
        _currentFlowStreak = 0;
        _longestFlowStreak = 0;
        _timeToFlow    = -1;
        _trend         = [] as Array<Number>;
        _bucketSum     = 0;
        _bucketCount   = 0;
        _rmssdSum      = 0.0;
        _hrvSampleCount = 0;
    }
}

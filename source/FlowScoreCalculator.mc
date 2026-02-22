import Toybox.Lang;
import Toybox.Math;

//! Calculates the Flow Score (0-100) from multi-sensor biofeedback
//!
//! Weighted composite based on research linking HRV to cognitive performance:
//! - HRV (RMSSD): 35% - Strongest predictor of cognitive performance
//! - HR Stability: 20% - Low variance = sustained arousal without anxiety
//! - Movement: 20% - Physical stillness indicates deep focus
//! - Stress: 20% - Garmin's composite HRV-based stress
//! - SpO2: 5% - Minor factor, only impacts if compromised
class FlowScoreCalculator {

    // Weights for each component
    private const WEIGHT_HRV = 0.35;
    private const WEIGHT_HR_STABILITY = 0.20;
    private const WEIGHT_MOVEMENT = 0.20;
    private const WEIGHT_STRESS = 0.20;
    private const WEIGHT_SPO2 = 0.05;

    // Current component scores (0-100)
    private var _hrvScore as Number = 50;
    private var _hrStabilityScore as Number = 50;
    private var _movementScore as Number = 50;
    private var _stressScore as Number = 50;
    private var _spo2Score as Number = 100;

    // Smoothing: exponential moving average
    private const EMA_ALPHA = 0.15;  // Lower = smoother (0.15 gives ~13s effective window)
    private var _emaScore as Float = 50.0;
    private var _emaInitialized as Boolean = false;

    // Computed flow score
    private var _flowScore as Number = 50;

    // Warm-up tracking: sensors need time to stabilize
    private const WARMUP_SAMPLES = 15;  // ~15 seconds of data
    private var _sampleCount as Number = 0;

    // Trend tracking: compare recent vs older scores
    private var _recentScores as Array<Number>;
    private const TREND_WINDOW = 30;  // 30 seconds of history
    private var _trend as Number = 0;  // -1 = declining, 0 = stable, 1 = improving

    // Session peak and min tracking
    private var _peakScore as Number = 0;
    private var _minScore as Number = 100;

    // Time-in-zone tracking (seconds spent in each zone)
    private var _timeInFlow as Number = 0;      // score >= 70
    private var _timeInFocus as Number = 0;      // score 40-69
    private var _timeInDistracted as Number = 0; // score < 40

    //! Constructor
    function initialize() {
        _recentScores = [] as Array<Number>;
    }

    //! Update sensor data and recalculate scores
    function updateSensorData(rmssd as Float, heartRate as Number, hrStdDev as Float,
                              accelMagnitude as Number, stress as Number, spo2 as Number) as Void {
        _sampleCount++;

        // Calculate individual component scores
        _hrvScore = calculateHrvScore(rmssd);
        _hrStabilityScore = calculateHrStabilityScore(hrStdDev);
        _movementScore = calculateMovementScore(accelMagnitude);
        _stressScore = calculateStressScore(stress);
        _spo2Score = calculateSpo2Score(spo2);

        // Calculate weighted composite
        var rawScore = (_hrvScore * WEIGHT_HRV) +
                      (_hrStabilityScore * WEIGHT_HR_STABILITY) +
                      (_movementScore * WEIGHT_MOVEMENT) +
                      (_stressScore * WEIGHT_STRESS) +
                      (_spo2Score * WEIGHT_SPO2);

        var rawInt = rawScore.toNumber();

        // Apply EMA smoothing
        if (!_emaInitialized) {
            _emaScore = rawInt.toFloat();
            _emaInitialized = true;
        } else {
            _emaScore = (EMA_ALPHA * rawInt) + ((1.0 - EMA_ALPHA) * _emaScore);
        }

        _flowScore = _emaScore.toNumber();
        if (_flowScore < 0) { _flowScore = 0; }
        if (_flowScore > 100) { _flowScore = 100; }

        // Track history for trend calculation
        _recentScores.add(_flowScore);
        if (_recentScores.size() > TREND_WINDOW) {
            _recentScores = _recentScores.slice(1, null) as Array<Number>;
        }
        updateTrend();

        // Update peak/min (only after warm-up)
        if (isWarmedUp()) {
            if (_flowScore > _peakScore) {
                _peakScore = _flowScore;
            }
            if (_flowScore < _minScore) {
                _minScore = _flowScore;
            }

            // Track time in zones
            if (_flowScore >= 70) {
                _timeInFlow++;
            } else if (_flowScore >= 40) {
                _timeInFocus++;
            } else {
                _timeInDistracted++;
            }
        }
    }

    //! Calculate trend from recent score history
    private function updateTrend() as Void {
        var size = _recentScores.size();
        if (size < 10) {
            _trend = 0;
            return;
        }

        // Compare average of last 5 vs average of 5 before that
        var recentSum = 0;
        var olderSum = 0;
        for (var i = size - 5; i < size; i++) {
            recentSum += _recentScores[i];
        }
        for (var i = size - 10; i < size - 5; i++) {
            olderSum += _recentScores[i];
        }

        var recentAvg = recentSum / 5;
        var olderAvg = olderSum / 5;
        var diff = recentAvg - olderAvg;

        if (diff > 3) {
            _trend = 1;   // Improving
        } else if (diff < -3) {
            _trend = -1;  // Declining
        } else {
            _trend = 0;   // Stable
        }
    }

    //! Calculate HRV score from RMSSD
    //! RMSSD 20ms = 0, 100ms = 100
    private function calculateHrvScore(rmssd as Float) as Number {
        if (rmssd <= 20.0) {
            return 0;
        }
        var score = ((rmssd - 20.0) * 1.25).toNumber();
        return clamp(score, 0, 100);
    }

    //! Calculate HR stability score from standard deviation
    //! stdDev 0 = 100, stdDev 10+ = 0
    private function calculateHrStabilityScore(hrStdDev as Float) as Number {
        var score = (100 - (hrStdDev * 10)).toNumber();
        return clamp(score, 0, 100);
    }

    //! Calculate movement score from accelerometer magnitude
    //! ~1000mg at rest (gravity), higher values indicate movement
    private function calculateMovementScore(accelMagnitude as Number) as Number {
        var excess = accelMagnitude - 1000;
        if (excess < 0) {
            excess = 0;
        }
        var score = (100 - (excess / 5)).toNumber();
        return clamp(score, 0, 100);
    }

    //! Calculate stress score (inverted - lower stress = higher score)
    private function calculateStressScore(stress as Number) as Number {
        if (stress <= 0) {
            return 50;  // Neutral if no stress data
        }
        return clamp(100 - stress, 0, 100);
    }

    //! Calculate SpO2 score
    //! 95%+ = 100, degrades below 95%
    private function calculateSpo2Score(spo2 as Number) as Number {
        if (spo2 <= 0) {
            return 100;  // Don't penalize if no data
        }
        if (spo2 >= 95) {
            return 100;
        }
        var score = ((spo2 - 85) * 10).toNumber();
        return clamp(score, 0, 100);
    }

    //! Clamp value between min and max
    private function clamp(value as Number, min as Number, max as Number) as Number {
        if (value < min) {
            return min;
        }
        if (value > max) {
            return max;
        }
        return value;
    }

    //! Check if sensors have warmed up enough for reliable readings
    function isWarmedUp() as Boolean {
        return _sampleCount >= WARMUP_SAMPLES;
    }

    //! Get warm-up progress (0-100)
    function getWarmupProgress() as Number {
        if (_sampleCount >= WARMUP_SAMPLES) {
            return 100;
        }
        return (_sampleCount * 100) / WARMUP_SAMPLES;
    }

    //! Get the current Flow Score (0-100)
    function getFlowScore() as Number {
        return _flowScore;
    }

    //! Get HRV component score
    function getHrvScore() as Number {
        return _hrvScore;
    }

    //! Get HR stability component score
    function getHrStabilityScore() as Number {
        return _hrStabilityScore;
    }

    //! Get movement component score
    function getMovementScore() as Number {
        return _movementScore;
    }

    //! Get stress component score
    function getStressScore() as Number {
        return _stressScore;
    }

    //! Get SpO2 component score
    function getSpo2Score() as Number {
        return _spo2Score;
    }

    //! Get flow zone label
    function getFlowZone() as String {
        if (_flowScore >= 70) {
            return "Flow";
        } else if (_flowScore >= 40) {
            return "Focus";
        } else {
            return "Distracted";
        }
    }

    //! Get trend direction: -1 = declining, 0 = stable, 1 = improving
    function getTrend() as Number {
        return _trend;
    }

    //! Get session peak score
    function getPeakScore() as Number {
        return _peakScore;
    }

    //! Get session minimum score
    function getMinScore() as Number {
        return _minScore;
    }

    //! Get seconds spent in Flow zone (score >= 70)
    function getTimeInFlow() as Number {
        return _timeInFlow;
    }

    //! Get seconds spent in Focus zone (score 40-69)
    function getTimeInFocus() as Number {
        return _timeInFocus;
    }

    //! Get seconds spent in Distracted zone (score < 40)
    function getTimeInDistracted() as Number {
        return _timeInDistracted;
    }

    //! Get total tracked time across all zones
    function getTotalTrackedTime() as Number {
        return _timeInFlow + _timeInFocus + _timeInDistracted;
    }

    //! Get flow zone percentage (time in Flow zone / total time)
    function getFlowZonePercent() as Number {
        var total = getTotalTrackedTime();
        if (total == 0) {
            return 0;
        }
        return (_timeInFlow * 100) / total;
    }

    //! Get the weakest component label (most dragging down the score)
    function getWeakestComponent() as String {
        var minVal = _hrvScore;
        var label = "HRV";

        if (_hrStabilityScore < minVal) {
            minVal = _hrStabilityScore;
            label = "HR Stability";
        }
        if (_movementScore < minVal) {
            minVal = _movementScore;
            label = "Movement";
        }
        if (_stressScore < minVal) {
            minVal = _stressScore;
            label = "Stress";
        }
        // SpO2 excluded as it's minor and usually 100

        return label;
    }

    //! Reset calculator state
    function reset() as Void {
        _hrvScore = 50;
        _hrStabilityScore = 50;
        _movementScore = 50;
        _stressScore = 50;
        _spo2Score = 100;
        _flowScore = 50;
        _emaScore = 50.0;
        _emaInitialized = false;
        _sampleCount = 0;
        _recentScores = [] as Array<Number>;
        _trend = 0;
        _peakScore = 0;
        _minScore = 100;
        _timeInFlow = 0;
        _timeInFocus = 0;
        _timeInDistracted = 0;
    }
}

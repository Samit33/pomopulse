import Toybox.Lang;
import Toybox.Math;

//! Calculates the Focus Quality score (0-100) from biofeedback signals
//!
//! Two-signal composite:
//! - HRV (RMSSD): 75% - Strongest predictor of cognitive performance
//! - Movement:    25% - Physical stillness indicates deep focus
//!
//! Stress, HR Stability, and SpO2 removed as unreliable on-device signals.
class FlowScoreCalculator {

    // Weights (must sum to 1.0)
    private const WEIGHT_HRV      = 0.75;
    private const WEIGHT_MOVEMENT = 0.25;

    // Current component scores (0-100)
    private var _hrvScore      as Number = 50;
    private var _movementScore as Number = 50;

    // Smoothing: exponential moving average
    private const EMA_ALPHA = 0.15;  // ~13 s effective window
    private var _emaScore       as Float   = 50.0;
    private var _emaInitialized as Boolean = false;

    // Computed flow score
    private var _flowScore as Number = 50;

    // Session peak and min tracking
    private var _peakScore as Number = 0;
    private var _minScore  as Number = 100;

    // Time-in-zone tracking (seconds spent in each zone)
    private var _timeInFlow       as Number = 0;  // score >= 70
    private var _timeInFocus      as Number = 0;  // score 40-69
    private var _timeInDistracted as Number = 0;  // score < 40

    // Track whether we received real biometric data
    private var _sampleCount as Number = 0;

    //! Constructor
    function initialize() {
    }

    //! Update sensor data and recalculate scores
    function updateSensorData(rmssd as Float, accelMagnitude as Number) as Void {
        _hrvScore      = calculateHrvScore(rmssd);
        _movementScore = calculateMovementScore(accelMagnitude);

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

        // Update peak/min
        if (_flowScore > _peakScore) { _peakScore = _flowScore; }
        if (_flowScore < _minScore)  { _minScore  = _flowScore; }

        // Track time in zones
        if (_flowScore >= 70) {
            _timeInFlow++;
        } else if (_flowScore >= 40) {
            _timeInFocus++;
        } else {
            _timeInDistracted++;
        }

        _sampleCount++;
    }

    //! HRV score: RMSSD 20ms = 0, 100ms = 100
    private function calculateHrvScore(rmssd as Float) as Number {
        if (rmssd <= 20.0) {
            return 0;
        }
        var score = ((rmssd - 20.0) * 1.25).toNumber();
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

    //! Whether real biometric data has been received
    function hasBiometrics() as Boolean {
        return _sampleCount > 0;
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

    //! Reset calculator state
    function reset() as Void {
        _hrvScore      = 50;
        _movementScore = 50;
        _flowScore     = 50;
        _emaScore      = 50.0;
        _emaInitialized = false;
        _peakScore     = 0;
        _minScore      = 100;
        _timeInFlow    = 0;
        _timeInFocus   = 0;
        _timeInDistracted = 0;
        _sampleCount   = 0;
    }
}

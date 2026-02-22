import Toybox.Lang;
import Toybox.Math;

//! Calculates the Focus Quality score (0-100) from biofeedback signals
//!
//! Simplified two-signal composite:
//! - HRV (RMSSD): 60% - Strongest predictor of cognitive performance
//! - Movement:    20% - Physical stillness indicates deep focus
//! - Stress:      20% - Garmin's composite HRV-based stress (inverted)
//!
//! HR Stability and SpO2 removed: HR rises naturally during focused work
//! (penalising that is counterproductive) and SpO2 barely changes during
//! cognitive effort, adding noise without insight.
class FlowScoreCalculator {

    // Weights for each component (must sum to 1.0)
    private const WEIGHT_HRV      = 0.60;
    private const WEIGHT_MOVEMENT = 0.20;
    private const WEIGHT_STRESS   = 0.20;

    // Current component scores (0-100)
    private var _hrvScore      as Number = 50;
    private var _movementScore as Number = 50;
    private var _stressScore   as Number = 50;

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

    //! Constructor
    function initialize() {
    }

    //! Update sensor data and recalculate scores
    function updateSensorData(rmssd as Float, accelMagnitude as Number,
                              stress as Number) as Void {
        // Calculate individual component scores
        _hrvScore      = calculateHrvScore(rmssd);
        _movementScore = calculateMovementScore(accelMagnitude);
        _stressScore   = calculateStressScore(stress);

        // Calculate weighted composite
        var rawScore = (_hrvScore      * WEIGHT_HRV) +
                       (_movementScore * WEIGHT_MOVEMENT) +
                       (_stressScore   * WEIGHT_STRESS);

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

    //! Calculate stress score (inverted — lower Garmin stress = higher score)
    private function calculateStressScore(stress as Number) as Number {
        if (stress <= 0) {
            return 50;  // Neutral if no stress data
        }
        return clamp(100 - stress, 0, 100);
    }

    //! Clamp value between min and max
    private function clamp(value as Number, min as Number, max as Number) as Number {
        if (value < min) { return min; }
        if (value > max) { return max; }
        return value;
    }

    //! Get the current flow score (0-100) — used for background FIT recording
    function getFlowScore() as Number {
        return _flowScore;
    }

    //! Get HRV component score (0-100)
    function getHrvScore() as Number {
        return _hrvScore;
    }

    //! Get movement component score (0-100)
    function getMovementScore() as Number {
        return _movementScore;
    }

    //! Get stress component score (0-100)
    function getStressScore() as Number {
        return _stressScore;
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

    //! Reset calculator state
    function reset() as Void {
        _hrvScore      = 50;
        _movementScore = 50;
        _stressScore   = 50;
        _flowScore     = 50;
        _emaScore      = 50.0;
        _emaInitialized = false;
        _peakScore     = 0;
        _minScore      = 100;
        _timeInFlow    = 0;
        _timeInFocus   = 0;
        _timeInDistracted = 0;
    }
}

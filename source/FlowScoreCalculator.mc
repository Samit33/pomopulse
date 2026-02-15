using Toybox.Math;
using Toybox.Lang;

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

    // Rolling average for smoothing
    private var _flowScoreHistory as Array<Number>;
    private const SMOOTHING_WINDOW = 5;

    // Computed flow score
    private var _flowScore as Number = 50;

    //! Constructor
    function initialize() {
        _flowScoreHistory = [] as Array<Number>;
    }

    //! Update sensor data and recalculate scores
    function updateSensorData(rmssd as Float, heartRate as Number, hrStdDev as Float,
                              accelMagnitude as Number, stress as Number, spo2 as Number) as Void {
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

        // Apply smoothing
        _flowScoreHistory.add(rawScore.toNumber());
        if (_flowScoreHistory.size() > SMOOTHING_WINDOW) {
            _flowScoreHistory = _flowScoreHistory.slice(1, null) as Array<Number>;
        }

        _flowScore = calculateSmoothedScore();
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
        // At rest, magnitude is ~1000 (1g gravity)
        // Movement adds to this baseline
        var excess = accelMagnitude - 1000;
        if (excess < 0) {
            excess = 0;
        }
        var score = (100 - (excess / 5)).toNumber();
        return clamp(score, 0, 100);
    }

    //! Calculate stress score (inverted - lower stress = higher score)
    //! Garmin stress is 0-100, we invert it
    private function calculateStressScore(stress as Number) as Number {
        if (stress <= 0) {
            return 50;  // Return neutral if no stress data
        }
        return clamp(100 - stress, 0, 100);
    }

    //! Calculate SpO2 score
    //! 95%+ = 100, degrades below 95%
    private function calculateSpo2Score(spo2 as Number) as Number {
        if (spo2 <= 0) {
            return 100;  // Return perfect if no SpO2 data (don't penalize)
        }
        if (spo2 >= 95) {
            return 100;
        }
        var score = ((spo2 - 85) * 10).toNumber();
        return clamp(score, 0, 100);
    }

    //! Calculate smoothed score from history
    private function calculateSmoothedScore() as Number {
        if (_flowScoreHistory.size() == 0) {
            return 50;
        }

        var sum = 0;
        for (var i = 0; i < _flowScoreHistory.size(); i++) {
            sum += _flowScoreHistory[i];
        }

        return sum / _flowScoreHistory.size();
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

    //! Reset calculator state
    function reset() as Void {
        _hrvScore = 50;
        _hrStabilityScore = 50;
        _movementScore = 50;
        _stressScore = 50;
        _spo2Score = 100;
        _flowScore = 50;
        _flowScoreHistory = [] as Array<Number>;
    }
}

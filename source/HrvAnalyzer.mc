import Toybox.Lang;
import Toybox.Math;

//! Analyzes heart beat intervals to calculate HRV metrics (RMSSD)
class HrvAnalyzer {

    // Beat-to-beat intervals in milliseconds
    private var _intervals as Array<Number>;
    private const MAX_INTERVALS = 60;  // Keep last 60 intervals (~1 minute)

    // Cached RMSSD value
    private var _rmssd as Float = 0.0;

    // Interval filtering thresholds
    private const MIN_INTERVAL_MS = 300;   // ~200 bpm max
    private const MAX_INTERVAL_MS = 2000;  // ~30 bpm min

    //! Constructor
    function initialize() {
        _intervals = [] as Array<Number>;
    }

    //! Reset analyzer state
    function reset() as Void {
        _intervals = [] as Array<Number>;
        _rmssd = 0.0;
    }

    //! Add a new R-R interval
    function addInterval(intervalMs as Number) as Void {
        // Filter out invalid intervals
        if (intervalMs < MIN_INTERVAL_MS || intervalMs > MAX_INTERVAL_MS) {
            return;
        }

        // Ectopic beat detection: reject if >30% change from previous
        if (_intervals.size() > 0) {
            var lastInterval = _intervals[_intervals.size() - 1];
            var change = (intervalMs - lastInterval).abs();
            var threshold = lastInterval * 0.3;
            if (change > threshold) {
                return;  // Likely ectopic beat or artifact
            }
        }

        _intervals.add(intervalMs);

        // Maintain window size
        if (_intervals.size() > MAX_INTERVALS) {
            _intervals = _intervals.slice(1, null) as Array<Number>;
        }

        // Recalculate RMSSD
        calculateRmssd();
    }

    //! Calculate RMSSD (Root Mean Square of Successive Differences)
    //! This is the primary HRV metric for parasympathetic activity
    private function calculateRmssd() as Void {
        if (_intervals.size() < 2) {
            _rmssd = 0.0;
            return;
        }

        // Calculate sum of squared successive differences
        var sumSquaredDiffs = 0.0;
        var count = 0;

        for (var i = 1; i < _intervals.size(); i++) {
            var diff = _intervals[i] - _intervals[i - 1];
            sumSquaredDiffs += (diff * diff);
            count++;
        }

        if (count == 0) {
            _rmssd = 0.0;
            return;
        }

        // RMSSD = sqrt(mean of squared differences)
        _rmssd = Math.sqrt(sumSquaredDiffs / count).toFloat();
    }

    //! Get current RMSSD value
    function getRmssd() as Float {
        return _rmssd;
    }

    //! Get number of intervals in buffer
    function getIntervalCount() as Number {
        return _intervals.size();
    }

    //! Get mean R-R interval (useful for HR calculation)
    function getMeanInterval() as Float {
        if (_intervals.size() == 0) {
            return 0.0;
        }

        var sum = 0.0;
        for (var i = 0; i < _intervals.size(); i++) {
            sum += _intervals[i];
        }

        return (sum / _intervals.size()).toFloat();
    }

    //! Calculate SDNN (Standard Deviation of NN intervals)
    //! Alternative HRV metric showing overall variability
    function getSdnn() as Float {
        if (_intervals.size() < 2) {
            return 0.0;
        }

        var mean = getMeanInterval();
        var sumSquaredDiffs = 0.0;

        for (var i = 0; i < _intervals.size(); i++) {
            var diff = _intervals[i] - mean;
            sumSquaredDiffs += (diff * diff);
        }

        return Math.sqrt(sumSquaredDiffs / _intervals.size()).toFloat();
    }

    //! Calculate pNN50 (percentage of successive intervals differing by >50ms)
    //! Another parasympathetic HRV indicator
    function getPnn50() as Float {
        if (_intervals.size() < 2) {
            return 0.0;
        }

        var count50 = 0;
        var totalDiffs = 0;

        for (var i = 1; i < _intervals.size(); i++) {
            var diff = (_intervals[i] - _intervals[i - 1]).abs();
            if (diff > 50) {
                count50++;
            }
            totalDiffs++;
        }

        if (totalDiffs == 0) {
            return 0.0;
        }

        return ((count50 * 100.0) / totalDiffs).toFloat();
    }
}

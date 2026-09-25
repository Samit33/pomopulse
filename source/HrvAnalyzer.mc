import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

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

    // Ectopic filter compares against the previous *raw* beat, and gives up
    // after a few rejections in a row (a genuine HR shift, not an artifact)
    private const MAX_CONSECUTIVE_REJECTS = 3;
    private var _lastRaw as Number = 0;
    private var _rejectStreak as Number = 0;

    // HRV is only trusted while clean beats keep arriving
    private const FRESH_MS = 5000;
    private const MIN_FRESH_INTERVALS = 10;
    private var _lastAcceptMs as Number = 0;

    //! Constructor
    function initialize() {
        _intervals = [] as Array<Number>;
    }

    //! Reset analyzer state
    function reset() as Void {
        _intervals = [] as Array<Number>;
        _rmssd = 0.0;
        _lastRaw = 0;
        _rejectStreak = 0;
        _lastAcceptMs = 0;
    }

    //! Add a new R-R interval
    function addInterval(intervalMs as Number) as Void {
        // Filter out invalid intervals
        if (intervalMs < MIN_INTERVAL_MS || intervalMs > MAX_INTERVAL_MS) {
            return;
        }

        // Ectopic beat detection: reject if >30% change from the previous beat.
        // Without the reject-streak escape, a real step change in heart rate
        // would lock the filter out forever.
        var previous = _lastRaw;
        _lastRaw = intervalMs;
        if (previous > 0) {
            var change = (intervalMs - previous).abs();
            if (change > previous * 0.3 && _rejectStreak < MAX_CONSECUTIVE_REJECTS) {
                _rejectStreak++;
                return;  // Likely ectopic beat or artifact
            }
        }
        _rejectStreak = 0;
        _lastAcceptMs = System.getTimer();

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

    //! True while enough clean beats are buffered and still arriving
    function isFresh() as Boolean {
        return _intervals.size() >= MIN_FRESH_INTERVALS &&
               (System.getTimer() - _lastAcceptMs) < FRESH_MS;
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

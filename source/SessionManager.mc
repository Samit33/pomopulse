import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

//! Manages FIT recording sessions with custom FlowScore field
class SessionManager {

    private var _session as ActivityRecording.Session?;
    private var _flowScoreField as FitContributor.Field?;
    private var _historyManager as HistoryManager?;

    // Session state
    private var _isRecording as Boolean = false;
    private var _isPaused as Boolean = false;
    private var _sessionStartTime as Time.Moment?;
    private var _flowScoreSum as Number = 0;
    private var _flowScoreSamples as Number = 0;

    // Richer session tracking
    private var _peakFlowScore as Number = 0;
    private var _minFlowScore as Number = 100;
    private var _timeInFlowZone as Number = 0;    // seconds with score >= 70
    private var _totalTrackedSeconds as Number = 0;

    // Custom field IDs
    private const FLOW_SCORE_FIELD_ID = 0;

    //! Constructor
    function initialize(historyManager as HistoryManager?) {
        _historyManager = historyManager;
    }

    //! Start a new recording session
    function startSession() as Void {
        if (_isRecording) {
            return;
        }

        try {
            _session = ActivityRecording.createSession({
                :name => "Focus Session",
                :sport => Activity.SPORT_GENERIC,
                :subSport => Activity.SUB_SPORT_GENERIC
            });

            if (_session == null) {
                System.println("Failed to create session");
                return;
            }

            _flowScoreField = _session.createField(
                "flow_score",
                FLOW_SCORE_FIELD_ID,
                FitContributor.DATA_TYPE_UINT8,
                {
                    :mesgType => FitContributor.MESG_TYPE_RECORD,
                    :units => "score"
                }
            );

            _session.start();
            _isRecording = true;
            _isPaused = false;
            _sessionStartTime = Time.now();
            _flowScoreSum = 0;
            _flowScoreSamples = 0;
            _peakFlowScore = 0;
            _minFlowScore = 100;
            _timeInFlowZone = 0;
            _totalTrackedSeconds = 0;

        } catch (ex) {
            System.println("Error starting session: " + ex.getErrorMessage());
            _session = null;
            _isRecording = false;
        }
    }

    //! Pause recording (keep session alive but stop writing data)
    function pauseSession() as Void {
        if (!_isRecording || _isPaused) {
            return;
        }
        _isPaused = true;
    }

    //! Resume recording after pause
    function resumeSession() as Void {
        if (!_isRecording || !_isPaused) {
            return;
        }
        _isPaused = false;
    }

    //! Record current flow score (call every second during session)
    function recordFlowScore(flowScore as Number) as Void {
        if (!_isRecording || _isPaused || _flowScoreField == null) {
            return;
        }

        try {
            _flowScoreField.setData(flowScore);

            _flowScoreSum += flowScore;
            _flowScoreSamples++;
            _totalTrackedSeconds++;

            // Track peak and min
            if (flowScore > _peakFlowScore) {
                _peakFlowScore = flowScore;
            }
            if (flowScore < _minFlowScore) {
                _minFlowScore = flowScore;
            }

            // Track time in flow zone
            if (flowScore >= 70) {
                _timeInFlowZone++;
            }

        } catch (ex) {
            System.println("Error recording flow score: " + ex.getErrorMessage());
        }
    }

    //! Stop the current recording session and save
    function stopSession() as Void {
        if (!_isRecording || _session == null) {
            return;
        }

        try {
            _session.stop();

            var avgFlowScore = 0;
            if (_flowScoreSamples > 0) {
                avgFlowScore = _flowScoreSum / _flowScoreSamples;
            }

            var durationSeconds = 0;
            if (_sessionStartTime != null) {
                var endTime = Time.now();
                durationSeconds = endTime.subtract(_sessionStartTime).value();
            }

            _session.save();

            // Save enriched data to local history
            var startTime = _sessionStartTime;
            if (_historyManager != null && durationSeconds > 0 && startTime != null) {
                var flowZonePct = 0;
                if (_totalTrackedSeconds > 0) {
                    flowZonePct = (_timeInFlowZone * 100) / _totalTrackedSeconds;
                }

                _historyManager.saveSession({
                    "timestamp" => startTime.value(),
                    "duration" => durationSeconds,
                    "avgFlowScore" => avgFlowScore,
                    "peakFlowScore" => _peakFlowScore,
                    "flowZonePercent" => flowZonePct,
                    "samples" => _flowScoreSamples
                });
            }

        } catch (ex) {
            System.println("Error stopping session: " + ex.getErrorMessage());
        }

        resetState();
    }

    //! Discard the current session without saving
    function discardSession() as Void {
        if (!_isRecording || _session == null) {
            return;
        }

        try {
            _session.stop();
            _session.discard();
        } catch (ex) {
            System.println("Error discarding session: " + ex.getErrorMessage());
        }

        resetState();
    }

    //! Reset internal state
    private function resetState() as Void {
        _session = null;
        _flowScoreField = null;
        _isRecording = false;
        _isPaused = false;
        _sessionStartTime = null;
        _flowScoreSum = 0;
        _flowScoreSamples = 0;
        _peakFlowScore = 0;
        _minFlowScore = 100;
        _timeInFlowZone = 0;
        _totalTrackedSeconds = 0;
    }

    //! Check if currently recording
    function isRecording() as Boolean {
        return _isRecording;
    }

    //! Check if currently paused
    function isPaused() as Boolean {
        return _isPaused;
    }

    //! Get current session duration in seconds
    function getSessionDuration() as Number {
        if (!_isRecording || _sessionStartTime == null) {
            return 0;
        }
        var now = Time.now();
        return now.subtract(_sessionStartTime).value();
    }

    //! Get current session average flow score
    function getSessionAvgFlowScore() as Number {
        if (_flowScoreSamples == 0) {
            return 0;
        }
        return _flowScoreSum / _flowScoreSamples;
    }

    //! Get session peak flow score
    function getSessionPeakFlowScore() as Number {
        return _peakFlowScore;
    }

    //! Get flow zone percentage for current session
    function getSessionFlowZonePercent() as Number {
        if (_totalTrackedSeconds == 0) {
            return 0;
        }
        return (_timeInFlowZone * 100) / _totalTrackedSeconds;
    }

    //! Get number of flow score samples recorded
    function getFlowScoreSamples() as Number {
        return _flowScoreSamples;
    }
}

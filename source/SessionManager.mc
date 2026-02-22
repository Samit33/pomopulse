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
    private var _sessionStartTime as Time.Moment?;
    private var _flowScoreSum as Number = 0;
    private var _flowScoreSamples as Number = 0;

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
            // Create activity session
            _session = ActivityRecording.createSession({
                :name => "Focus Session",
                :sport => Activity.SPORT_GENERIC,
                :subSport => Activity.SUB_SPORT_GENERIC
            });

            if (_session == null) {
                System.println("Failed to create session");
                return;
            }

            // Create custom FlowScore field
            _flowScoreField = _session.createField(
                "flow_score",
                FLOW_SCORE_FIELD_ID,
                FitContributor.DATA_TYPE_UINT8,
                {
                    :mesgType => FitContributor.MESG_TYPE_RECORD,
                    :units => "score"
                }
            );

            // Start recording
            _session.start();
            _isRecording = true;
            _sessionStartTime = Time.now();
            _flowScoreSum = 0;
            _flowScoreSamples = 0;

        } catch (ex) {
            System.println("Error starting session: " + ex.getErrorMessage());
            _session = null;
            _isRecording = false;
        }
    }

    //! Record current flow score (call every second during session)
    function recordFlowScore(flowScore as Number) as Void {
        if (!_isRecording || _flowScoreField == null) {
            return;
        }

        try {
            // Write per-second flow score to FIT record
            _flowScoreField.setData(flowScore);

            // Track for session average
            _flowScoreSum += flowScore;
            _flowScoreSamples++;

        } catch (ex) {
            System.println("Error recording flow score: " + ex.getErrorMessage());
        }
    }

    //! Stop the current recording session
    function stopSession() as Void {
        if (!_isRecording || _session == null) {
            return;
        }

        try {
            // Stop and save session
            _session.stop();

            // Calculate session average
            var avgFlowScore = 0;
            if (_flowScoreSamples > 0) {
                avgFlowScore = _flowScoreSum / _flowScoreSamples;
            }

            // Calculate session duration
            var durationSeconds = 0;
            if (_sessionStartTime != null) {
                var endTime = Time.now();
                durationSeconds = endTime.subtract(_sessionStartTime).value();
            }

            // Save to FIT file
            _session.save();

            // Save to local history
            var startTime = _sessionStartTime;
            if (_historyManager != null && durationSeconds > 0 && startTime != null) {
                _historyManager.saveSession({
                    "timestamp" => startTime.value(),
                    "duration" => durationSeconds,
                    "avgFlowScore" => avgFlowScore,
                    "samples" => _flowScoreSamples
                });
            }

        } catch (ex) {
            System.println("Error stopping session: " + ex.getErrorMessage());
        }

        // Reset state
        _session = null;
        _flowScoreField = null;
        _isRecording = false;
        _sessionStartTime = null;
        _flowScoreSum = 0;
        _flowScoreSamples = 0;
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

        // Reset state
        _session = null;
        _flowScoreField = null;
        _isRecording = false;
        _sessionStartTime = null;
        _flowScoreSum = 0;
        _flowScoreSamples = 0;
    }

    //! Check if currently recording
    function isRecording() as Boolean {
        return _isRecording;
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

    //! Get number of flow score samples recorded
    function getFlowScoreSamples() as Number {
        return _flowScoreSamples;
    }
}

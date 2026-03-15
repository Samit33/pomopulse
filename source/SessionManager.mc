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

    // Flow score aggregates
    private var _flowScoreSum as Number = 0;
    private var _flowScoreSamples as Number = 0;
    private var _peakFlowScore as Number = 0;
    private var _minFlowScore as Number = 100;
    private var _timeInFlowZone as Number = 0;

    // Active time (excludes paused time)
    private var _activeSeconds as Number = 0;

    // Mode/label/converted metadata
    private var _mode as Number = 0;          // 0=Flowtimer, 1=Pomodoro
    private var _converted as Boolean = false;

    private const FLOW_SCORE_FIELD_ID = 0;
    private const MIN_SESSION_SECONDS = 600;  // 10 minutes

    //! Constructor
    function initialize(historyManager as HistoryManager?) {
        _historyManager = historyManager;
    }

    //! Set session mode before starting
    function setSessionMode(mode as Number) as Void {
        _mode = mode;
    }

    //! Mark session as converted (abandoned Pomodoro → Flowtimer)
    function setConverted(converted as Boolean) as Void {
        _converted = converted;
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

            var session = _session;
            _flowScoreField = session.createField(
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
            _activeSeconds = 0;
            _converted = false;

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

    //! Record current flow score (call every second during active session)
    function recordFlowScore(flowScore as Number) as Void {
        if (!_isRecording || _isPaused || _flowScoreField == null) {
            return;
        }

        try {
            _flowScoreField.setData(flowScore);

            _flowScoreSum += flowScore;
            _flowScoreSamples++;
            _activeSeconds++;

            if (flowScore > _peakFlowScore) {
                _peakFlowScore = flowScore;
            }
            if (flowScore < _minFlowScore) {
                _minFlowScore = flowScore;
            }
            if (flowScore >= 70) {
                _timeInFlowZone++;
            }

        } catch (ex) {
            System.println("Error recording flow score: " + ex.getErrorMessage());
        }
    }

    //! Stop and save session (returns true if saved, false if discarded due to short duration)
    function stopSession() as Boolean {
        if (!_isRecording || _session == null) {
            return false;
        }

        var saved = false;
        var session = _session;

        try {
            session.stop();

            if (_activeSeconds >= MIN_SESSION_SECONDS) {
                var avgFlowScore = 0;
                if (_flowScoreSamples > 0) {
                    avgFlowScore = _flowScoreSum / _flowScoreSamples;
                }

                session.save();

                // Compute session label
                var label;
                if (_mode == MODE_FLOWTIMER || _converted) {
                    label = getFlowLabel(_activeSeconds);
                } else {
                    label = "Pomodoro";
                }

                // Save to local history
                var startTime = _sessionStartTime;
                var hm = _historyManager;
                if (hm != null && startTime != null) {
                    var flowZonePct = 0;
                    if (_activeSeconds > 0) {
                        flowZonePct = (_timeInFlowZone * 100) / _activeSeconds;
                    }

                    hm.saveSession({
                        "timestamp" => startTime.value(),
                        "duration" => _activeSeconds,
                        "avgFlowScore" => avgFlowScore,
                        "peakFlowScore" => _peakFlowScore,
                        "flowZonePercent" => flowZonePct,
                        "samples" => _flowScoreSamples,
                        "mode" => _mode,
                        "label" => label,
                        "converted" => _converted
                    });
                }

                saved = true;
            } else {
                session.discard();
            }

        } catch (ex) {
            System.println("Error stopping session: " + ex.getErrorMessage());
        }

        resetState();
        return saved;
    }

    //! Discard the current session without saving
    function discardSession() as Void {
        if (!_isRecording || _session == null) {
            return;
        }

        var session = _session;
        try {
            if (session != null) {
                session.stop();
                session.discard();
            }
        } catch (ex) {
            System.println("Error discarding session: " + ex.getErrorMessage());
        }

        resetState();
    }

    //! Derive Flowtimer label from duration
    private function getFlowLabel(seconds as Number) as String {
        var mins = seconds / 60;
        if (mins < 25) {
            return "Short flow";
        } else if (mins < 60) {
            return "Deep flow";
        } else {
            return "Extended flow";
        }
    }

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
        _activeSeconds = 0;
        _converted = false;
    }

    function isRecording() as Boolean {
        return _isRecording;
    }

    function isPaused() as Boolean {
        return _isPaused;
    }

    //! Get active session duration (excludes paused time)
    function getSessionDuration() as Number {
        return _activeSeconds;
    }

    function getSessionAvgFlowScore() as Number {
        if (_flowScoreSamples == 0) {
            return 0;
        }
        return _flowScoreSum / _flowScoreSamples;
    }

    function getSessionPeakFlowScore() as Number {
        return _peakFlowScore;
    }

    function getSessionFlowZonePercent() as Number {
        if (_activeSeconds == 0) {
            return 0;
        }
        return (_timeInFlowZone * 100) / _activeSeconds;
    }

    function getFlowScoreSamples() as Number {
        return _flowScoreSamples;
    }

    //! Minimum session duration in seconds
    function getMinSessionSeconds() as Number {
        return MIN_SESSION_SECONDS;
    }
}

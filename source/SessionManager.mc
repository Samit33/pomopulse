import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

//! Manages FIT recording (per-second Depth, plus session-level Quality,
//! Deep Minutes and Interruptions) and writes finished sessions to history.
class SessionManager {

    private var _session as ActivityRecording.Session?;
    private var _depthField         as FitContributor.Field?;
    private var _qualityField       as FitContributor.Field?;
    private var _deepMinutesField   as FitContributor.Field?;
    private var _interruptionsField as FitContributor.Field?;
    private var _historyManager as HistoryManager?;

    // Session state
    private var _isRecording as Boolean = false;
    private var _isPaused as Boolean = false;
    private var _sessionStartTime as Time.Moment?;

    // Depth aggregates
    private var _depthSum as Number = 0;
    private var _depthSamples as Number = 0;

    // Active time (excludes paused time)
    private var _activeSeconds as Number = 0;

    // Mode/label/converted metadata
    private var _mode as Number = 0;          // 0=Flowtimer, 1=Pomodoro
    private var _converted as Boolean = false;

    // Engine-derived fields merged into the history record on save
    private var _extras as Dictionary?;

    // Timestamp of the last session written to history (for self-rating)
    private var _lastSavedTimestamp as Number = 0;

    private const DEPTH_FIELD_ID         = 0;
    private const QUALITY_FIELD_ID       = 1;
    private const DEEP_MINUTES_FIELD_ID  = 2;
    private const INTERRUPTIONS_FIELD_ID = 3;
    private const MIN_SESSION_SECONDS = 600;  // 10 minutes

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

    //! Attach engine-derived session fields (quality, deep time, ...)
    //! just before stopping the session
    function setSessionExtras(extras as Dictionary) as Void {
        _extras = extras;
    }

    //! Start a new recording session
    function startSession() as Void {
        if (_isRecording) {
            return;
        }

        try {
            var session = ActivityRecording.createSession({
                :name => "Deep Work",
                :sport => Activity.SPORT_GENERIC,
                :subSport => Activity.SUB_SPORT_GENERIC
            });
            _session = session;

            _depthField = session.createField("depth", DEPTH_FIELD_ID,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "depth"});
            _qualityField = session.createField("deep_quality", QUALITY_FIELD_ID,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "score"});
            _deepMinutesField = session.createField("deep_minutes", DEEP_MINUTES_FIELD_ID,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "min"});
            _interruptionsField = session.createField("interruptions", INTERRUPTIONS_FIELD_ID,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "count"});

            session.start();
            _isRecording = true;
            _isPaused = false;
            _sessionStartTime = Time.now();
            _depthSum = 0;
            _depthSamples = 0;
            _activeSeconds = 0;
            _converted = false;
            _extras = null;

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

    //! Record current depth (call every second during active focus)
    function recordDepth(depth as Number) as Void {
        if (!_isRecording || _isPaused) {
            return;
        }
        _activeSeconds++;
        _depthSum += depth;
        _depthSamples++;

        var field = _depthField;
        if (field != null) {
            try {
                field.setData(depth);
            } catch (ex) {
                System.println("Error recording depth: " + ex.getErrorMessage());
            }
        }
    }

    //! Stop and save session. Returns true if saved, false if discarded
    //! for being under the 10-minute floor.
    function stopSession() as Boolean {
        var session = _session;
        if (!_isRecording || session == null) {
            return false;
        }

        var saved = false;

        try {
            if (_activeSeconds >= MIN_SESSION_SECONDS) {
                writeSessionFields();
                session.stop();

                // Only write the FIT activity (which syncs to Garmin Connect, and
                // onward to Strava) when the user has sync enabled. Local history
                // below is kept either way, so the app's own stats are unaffected.
                if (isGarminSyncEnabled()) {
                    session.save();
                } else {
                    session.discard();
                }

                saveToHistory();
                saved = true;
            } else {
                session.stop();
                session.discard();
            }

        } catch (ex) {
            System.println("Error stopping session: " + ex.getErrorMessage());
        }

        resetState();
        return saved;
    }

    //! Session-level FIT fields shown in the Garmin Connect activity summary
    private function writeSessionFields() as Void {
        var extras = _extras;
        if (extras == null) {
            return;
        }
        var q = _qualityField;
        if (q != null && extras.hasKey("quality")) {
            q.setData(extras["quality"] as Number);
        }
        var dm = _deepMinutesField;
        if (dm != null && extras.hasKey("deepSec")) {
            dm.setData((extras["deepSec"] as Number) / 60);
        }
        var intr = _interruptionsField;
        if (intr != null && extras.hasKey("intr")) {
            intr.setData(extras["intr"] as Number);
        }
    }

    private function saveToHistory() as Void {
        var startTime = _sessionStartTime;
        var hm = _historyManager;
        if (hm == null || startTime == null) {
            return;
        }

        var label;
        if (_mode == MODE_FLOWTIMER || _converted) {
            label = getFlowLabel(_activeSeconds);
        } else {
            label = "Pomodoro";
        }

        var avgDepth = _depthSamples > 0 ? _depthSum / _depthSamples : 0;
        var record = {
            "timestamp"    => startTime.value(),
            "duration"     => _activeSeconds,
            "avgFlowScore" => avgDepth,   // Legacy key: average depth
            "samples"      => _depthSamples,
            "mode"         => _mode,
            "label"        => label,
            "converted"    => _converted
        } as Dictionary;

        var extras = _extras;
        if (extras != null) {
            var keys = extras.keys();
            for (var i = 0; i < keys.size(); i++) {
                record[keys[i]] = extras[keys[i]];
            }
        }

        hm.saveSession(record);
        _lastSavedTimestamp = startTime.value();
    }

    //! Discard the current session without saving
    function discardSession() as Void {
        var session = _session;
        if (!_isRecording || session == null) {
            return;
        }

        try {
            session.stop();
            session.discard();
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
        _depthField = null;
        _qualityField = null;
        _deepMinutesField = null;
        _interruptionsField = null;
        _isRecording = false;
        _isPaused = false;
        _sessionStartTime = null;
        _depthSum = 0;
        _depthSamples = 0;
        _activeSeconds = 0;
        _converted = false;
        _extras = null;
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

    //! Start timestamp of the most recently saved session
    function getLastSavedTimestamp() as Number {
        return _lastSavedTimestamp;
    }

    //! Minimum session duration in seconds
    function getMinSessionSeconds() as Number {
        return MIN_SESSION_SECONDS;
    }
}

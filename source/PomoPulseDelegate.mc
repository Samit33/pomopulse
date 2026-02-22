import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Input handler for the main timer view
class PomoPulseDelegate extends WatchUi.BehaviorDelegate {

    private var _timerController as TimerController?;
    private var _sensorManager as SensorManager?;
    private var _sessionManager as SessionManager?;
    private var _flowCalculator as FlowScoreCalculator?;
    private var _view as PomoPulseView?;

    //! Constructor
    function initialize(timerController as TimerController?, sensorManager as SensorManager?,
                       sessionManager as SessionManager?, flowCalculator as FlowScoreCalculator?,
                       view as PomoPulseView?) {
        BehaviorDelegate.initialize();
        _timerController = timerController;
        _sensorManager = sensorManager;
        _sessionManager = sessionManager;
        _flowCalculator = flowCalculator;
        _view = view;
    }

    //! Handle select button (START/STOP button on FR255)
    function onSelect() as Boolean {
        var tc = _timerController;
        if (tc == null) {
            return false;
        }

        if (tc.isRunning()) {
            // Pause timer - pause recording but keep session alive
            tc.pause();
            pauseRecording();
        } else {
            // Start/resume timer
            if (tc.getState() == STATE_IDLE) {
                // Fresh start - begin new recording
                tc.start();
                startRecording();
            } else {
                // Resuming from pause - resume existing recording
                tc.start();
                resumeRecording();
            }
        }

        WatchUi.requestUpdate();
        return true;
    }

    //! Handle back button (LAP/BACK on FR255)
    function onBack() as Boolean {
        var tc = _timerController;
        if (tc == null) {
            return false;
        }

        // If running or paused, stop and reset
        if (tc.getState() != STATE_IDLE) {
            // Stop any active recording/sensors
            stopRecording();
            tc.resetToWork();
            if (_flowCalculator != null) {
                _flowCalculator.reset();
            }
            WatchUi.requestUpdate();
            return true;
        }

        // If idle, exit app
        return false;
    }

    //! Handle menu button (UP button long press)
    function onMenu() as Boolean {
        var menu = new SettingsMenu();
        var delegate = new SettingsMenuDelegate(_timerController);
        WatchUi.pushView(menu, delegate, WatchUi.SLIDE_UP);
        return true;
    }

    //! Handle UP button press
    function onPreviousPage() as Boolean {
        var statsView = new StatsView(getApp().getHistoryManager());
        var statsDelegate = new StatsDelegate();
        WatchUi.pushView(statsView, statsDelegate, WatchUi.SLIDE_UP);
        return true;
    }

    //! Handle DOWN button press
    function onNextPage() as Boolean {
        var tc = _timerController;
        if (tc == null) {
            return false;
        }

        // Skip current phase
        if (tc.isWorkState()) {
            if (tc.isRunning() || tc.getState() == STATE_WORK_PAUSED) {
                stopRecordingAndShowSummary();
            }
            tc.skipToBreak();
        } else {
            tc.skipToWork();
            if (_flowCalculator != null) {
                _flowCalculator.reset();
            }
            // Don't start recording - user presses START to begin next session
        }

        WatchUi.requestUpdate();
        return true;
    }

    //! Start recording session and sensors
    private function startRecording() as Void {
        if (_sensorManager != null) {
            _sensorManager.startSensors();
        }
        if (_sessionManager != null) {
            _sessionManager.startSession();
        }
    }

    //! Pause recording (keep session alive, pause sensors)
    private function pauseRecording() as Void {
        if (_sessionManager != null) {
            _sessionManager.pauseSession();
        }
        // Keep sensors running but the session won't record data
    }

    //! Resume recording
    private function resumeRecording() as Void {
        var sensor = _sensorManager;
        if (sensor != null && !sensor.areSensorsEnabled()) {
            sensor.startSensors();
        }
        if (_sessionManager != null) {
            _sessionManager.resumeSession();
        }
    }

    //! Stop recording and save session
    private function stopRecording() as Void {
        if (_sessionManager != null) {
            _sessionManager.stopSession();
        }
        if (_sensorManager != null) {
            _sensorManager.stopSensors();
        }
    }

    //! Stop recording, save, and show session summary
    private function stopRecordingAndShowSummary() as Void {
        var duration = 0;
        var hrvScore = 50;
        var movementScore = 50;
        var stressScore = 50;

        var sm = _sessionManager;
        if (sm != null) {
            duration = sm.getSessionDuration();
        }

        var fc = _flowCalculator;
        if (fc != null) {
            hrvScore      = fc.getHrvScore();
            movementScore = fc.getMovementScore();
            stressScore   = fc.getStressScore();
        }

        stopRecording();

        // Show summary if we have meaningful data (at least 30s of recording)
        if (duration >= 30) {
            var summaryView = new SessionSummaryView(duration, hrvScore, movementScore, stressScore);
            var summaryDelegate = new SessionSummaryDelegate();
            WatchUi.pushView(summaryView, summaryDelegate, WatchUi.SLIDE_UP);
        }
    }

    //! Called by TimerController when a work phase completes naturally
    function onWorkPhaseComplete() as Void {
        stopRecordingAndShowSummary();
    }
}

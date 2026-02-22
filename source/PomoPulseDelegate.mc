import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Input handler for the main timer view
class PomoPulseDelegate extends WatchUi.BehaviorDelegate {

    private var _timerController as TimerController?;
    private var _sensorManager as SensorManager?;
    private var _sessionManager as SessionManager?;
    private var _view as PomoPulseView?;

    //! Constructor
    function initialize(timerController as TimerController?, sensorManager as SensorManager?,
                       sessionManager as SessionManager?, view as PomoPulseView?) {
        BehaviorDelegate.initialize();
        _timerController = timerController;
        _sensorManager = sensorManager;
        _sessionManager = sessionManager;
        _view = view;
    }

    //! Handle select button (START/STOP button on FR255)
    function onSelect() as Boolean {
        var tc = _timerController;
        if (tc == null) {
            return false;
        }

        if (tc.isRunning()) {
            // Pause timer
            tc.pause();
            stopRecording();
        } else {
            // Start timer
            tc.start();
            startRecording();
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

        // If running or paused, reset timer
        if (tc.getState() != STATE_IDLE) {
            if (tc.isRunning()) {
                stopRecording();
            }
            tc.resetToWork();
            WatchUi.requestUpdate();
            return true;
        }

        // If idle, exit app
        return false;
    }

    //! Handle menu button (UP button long press)
    function onMenu() as Boolean {
        // Open settings menu
        var menu = new SettingsMenu();
        var delegate = new SettingsMenuDelegate(_timerController);
        WatchUi.pushView(menu, delegate, WatchUi.SLIDE_UP);
        return true;
    }

    //! Handle UP button press
    function onPreviousPage() as Boolean {
        // Show stats view
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
            // Stop recording if running
            if (tc.isRunning()) {
                stopRecording();
            }
            tc.skipToBreak();
        } else {
            tc.skipToWork();
            startRecording();
        }

        WatchUi.requestUpdate();
        return true;
    }

    //! Start recording session
    private function startRecording() as Void {
        if (_sensorManager != null) {
            _sensorManager.startSensors();
        }
        if (_sessionManager != null) {
            _sessionManager.startSession();
        }
    }

    //! Stop recording session
    private function stopRecording() as Void {
        if (_sessionManager != null) {
            _sessionManager.stopSession();
        }
        if (_sensorManager != null) {
            _sensorManager.stopSensors();
        }
    }
}

using Toybox.WatchUi;
using Toybox.System;

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
        if (_timerController == null) {
            return false;
        }

        if (_timerController.isRunning()) {
            // Pause timer
            _timerController.pause();
            stopRecording();
        } else {
            // Start timer
            _timerController.start();
            startRecording();
        }

        WatchUi.requestUpdate();
        return true;
    }

    //! Handle back button (LAP/BACK on FR255)
    function onBack() as Boolean {
        if (_timerController == null) {
            return false;
        }

        // If running or paused, reset timer
        if (_timerController.getState() != STATE_IDLE) {
            if (_timerController.isRunning()) {
                stopRecording();
            }
            _timerController.resetToWork();
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
        if (_timerController == null) {
            return false;
        }

        // Skip current phase
        if (_timerController.isWorkState()) {
            // Stop recording if running
            if (_timerController.isRunning()) {
                stopRecording();
            }
            _timerController.skipToBreak();
        } else {
            _timerController.skipToWork();
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

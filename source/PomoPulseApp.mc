import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;

//! Main application entry point for PomoPulse
class PomoPulseApp extends Application.AppBase {

    private var _timerController as TimerController?;
    private var _sensorManager as SensorManager?;
    private var _flowCalculator as FlowScoreCalculator?;
    private var _sessionManager as SessionManager?;
    private var _historyManager as HistoryManager?;

    //! Constructor
    function initialize() {
        AppBase.initialize();
    }

    //! Called on application start
    function onStart(state as Dictionary?) as Void {
        _historyManager = new HistoryManager();
        _timerController = new TimerController();
        _flowCalculator = new FlowScoreCalculator();
        _sensorManager = new SensorManager(_flowCalculator);
        _sessionManager = new SessionManager(_historyManager);
    }

    //! Called on application stop
    function onStop(state as Dictionary?) as Void {
        if (_sensorManager != null) {
            _sensorManager.stopSensors();
        }
        if (_sessionManager != null) {
            _sessionManager.stopSession();
        }
    }

    //! Return the initial view of your application
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new PomoPulseView(_timerController, _flowCalculator, _sensorManager, _sessionManager);
        var delegate = new PomoPulseDelegate(_timerController, _sensorManager, _sessionManager, _flowCalculator, view);

        // Wire up work-complete callback so delegate can show summary
        if (_timerController != null) {
            _timerController.setWorkCompleteCallback(method(:onWorkPhaseComplete));
        }

        return [view, delegate];
    }

    //! Called when a work phase completes naturally
    function onWorkPhaseComplete() as Void {
        // Stop recording and show summary
        var avgFlow = 0;
        var peakFlow = 0;
        var flowZonePct = 0;
        var duration = 0;
        var weakest = "";

        if (_sessionManager != null) {
            avgFlow = _sessionManager.getSessionAvgFlowScore();
            peakFlow = _sessionManager.getSessionPeakFlowScore();
            flowZonePct = _sessionManager.getSessionFlowZonePercent();
            duration = _sessionManager.getSessionDuration();
            _sessionManager.stopSession();
        }
        if (_sensorManager != null) {
            _sensorManager.stopSensors();
        }
        if (_flowCalculator != null) {
            weakest = _flowCalculator.getWeakestComponent();
        }

        // Show summary if meaningful session (at least 30s)
        if (duration >= 30) {
            var summaryView = new SessionSummaryView(avgFlow, peakFlow, flowZonePct, duration, weakest);
            var summaryDelegate = new SessionSummaryDelegate();
            WatchUi.pushView(summaryView, summaryDelegate, WatchUi.SLIDE_UP);
        }
    }

    //! Get the timer controller instance
    function getTimerController() as TimerController? {
        return _timerController;
    }

    //! Get the sensor manager instance
    function getSensorManager() as SensorManager? {
        return _sensorManager;
    }

    //! Get the flow calculator instance
    function getFlowCalculator() as FlowScoreCalculator? {
        return _flowCalculator;
    }

    //! Get the session manager instance
    function getSessionManager() as SessionManager? {
        return _sessionManager;
    }

    //! Get the history manager instance
    function getHistoryManager() as HistoryManager? {
        return _historyManager;
    }
}

//! Get the application instance
function getApp() as PomoPulseApp {
    return Application.getApp() as PomoPulseApp;
}

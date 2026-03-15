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
    private var _delegate as PomoPulseDelegate?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        _historyManager = new HistoryManager();
        _timerController = new TimerController();
        _flowCalculator = new FlowScoreCalculator();
        _sensorManager = new SensorManager(_flowCalculator);
        _sessionManager = new SessionManager(_historyManager);
    }

    function onStop(state as Dictionary?) as Void {
        if (_sensorManager != null) {
            _sensorManager.stopSensors();
        }
        if (_sessionManager != null) {
            _sessionManager.stopSession();
        }
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new PomoPulseView(_timerController, _flowCalculator, _sensorManager, _sessionManager);
        var delegate = new PomoPulseDelegate(_timerController, _sensorManager, _sessionManager, _flowCalculator, view);
        _delegate = delegate;

        // Wire up timer callbacks
        var tc = _timerController;
        if (tc != null) {
            tc.setWorkCompleteCallback(method(:onWorkPhaseComplete));
            tc.setAutoStopCallback(method(:onAutoStop));
            tc.setCycleCompleteCallback(method(:onCycleComplete));
        }

        return [view, delegate];
    }

    //! Pomodoro work phase completed naturally
    function onWorkPhaseComplete() as Void {
        var duration = 0;
        var hrvScore = 50;
        var movementScore = 50;
        var hasBiometrics = false;

        var sm = _sessionManager;
        if (sm != null) {
            duration = sm.getSessionDuration();
            sm.stopSession();
        }
        if (_sensorManager != null) {
            _sensorManager.stopSensors();
        }
        var fc = _flowCalculator;
        if (fc != null) {
            hrvScore      = fc.getHrvScore();
            movementScore = fc.getMovementScore();
            hasBiometrics = fc.hasBiometrics();
            fc.reset();
        }

        if (duration >= 600) {
            var summaryView = new SessionSummaryView(duration, hrvScore, movementScore,
                                                      MODE_POMODORO, "Pomodoro", false, hasBiometrics);
            var summaryDelegate = new SessionSummaryDelegate();
            WatchUi.pushView(summaryView, summaryDelegate, WatchUi.SLIDE_UP);
        }
    }

    //! Flowtimer auto-stop (120-min ceiling or 15-min pause timeout)
    function onAutoStop() as Void {
        if (_delegate != null) {
            _delegate.onAutoStop();
        }
    }

    //! Pomodoro cycle complete (4 sessions done)
    function onCycleComplete() as Void {
        var hm = _historyManager;
        if (hm == null) { return; }

        var completedCycles = hm.getTodayCompletedCycles();

        // Get cycle-specific stats from the last 4 Pomodoro sessions
        var pomoSessions = hm.getTodaySessionsByMode(MODE_POMODORO);
        var cycleFocusTime = 0;
        var cycleFlowSum = 0;
        var cycleSamples = 0;
        var count = pomoSessions.size() < 4 ? pomoSessions.size() : 4;
        for (var i = 0; i < count; i++) {
            var session = pomoSessions[i];
            if (session.hasKey("duration")) {
                cycleFocusTime += (session["duration"] as Number);
            }
            if (session.hasKey("avgFlowScore") && session.hasKey("samples")) {
                cycleFlowSum += (session["avgFlowScore"] as Number) * (session["samples"] as Number);
                cycleSamples += (session["samples"] as Number);
            }
        }
        var cycleAvgFlow = cycleSamples > 0 ? cycleFlowSum / cycleSamples : 0;
        var hasBiometrics = cycleSamples > 0;

        var summaryView = new CycleSummaryView(cycleFocusTime, cycleAvgFlow,
                                                hasBiometrics, completedCycles);
        var summaryDelegate = new CycleSummaryDelegate();
        WatchUi.pushView(summaryView, summaryDelegate, WatchUi.SLIDE_UP);
    }

    function getTimerController() as TimerController? {
        return _timerController;
    }

    function getSensorManager() as SensorManager? {
        return _sensorManager;
    }

    function getFlowCalculator() as FlowScoreCalculator? {
        return _flowCalculator;
    }

    function getSessionManager() as SessionManager? {
        return _sessionManager;
    }

    function getHistoryManager() as HistoryManager? {
        return _historyManager;
    }
}

function getApp() as PomoPulseApp {
    return Application.getApp() as PomoPulseApp;
}

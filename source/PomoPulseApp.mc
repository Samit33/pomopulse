import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;

//! Main application entry point for PomoPulse
class PomoPulseApp extends Application.AppBase {

    private var _timerController as TimerController?;
    private var _sensorManager as SensorManager?;
    private var _engine as DeepWorkEngine?;
    private var _sessionManager as SessionManager?;
    private var _historyManager as HistoryManager?;
    private var _delegate as PomoPulseDelegate?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        _historyManager = new HistoryManager();
        _timerController = new TimerController();
        _engine = new DeepWorkEngine();
        _sensorManager = new SensorManager(_engine);
        _sessionManager = new SessionManager(_historyManager);
    }

    function onStop(state as Dictionary?) as Void {
        if (_sensorManager != null) {
            _sensorManager.stopSensors();
        }
        var sm = _sessionManager;
        if (sm != null) {
            // App closed mid-session: keep the deep-work metrics with it
            var engine = _engine;
            if (engine != null && sm.isRecording()) {
                sm.setSessionExtras(engine.getSessionRecord());
            }
            sm.stopSession();
        }
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new PomoPulseView(_timerController, _engine, _sensorManager, _sessionManager);
        var delegate = new PomoPulseDelegate(_timerController, _sensorManager, _sessionManager, _engine, view);
        _delegate = delegate;

        // Wire up timer callbacks
        var tc = _timerController;
        if (tc != null) {
            tc.setWorkCompleteCallback(method(:onWorkPhaseComplete));
            tc.setAutoStopCallback(method(:onAutoStop));
            tc.setCycleCompleteCallback(method(:onCycleComplete));
            tc.setRecordCallback(method(:onRecordTick));
        }

        return [view, delegate];
    }

    //! Per-second recording during active focus. Lives at app level so
    //! depth keeps being recorded even while stats/settings views are open.
    function onRecordTick() as Void {
        var engine = _engine;
        var sm = _sessionManager;
        if (engine != null && sm != null) {
            sm.recordDepth(engine.getDepth());
        }
    }

    //! Pomodoro work phase completed naturally
    function onWorkPhaseComplete() as Void {
        finishSession(MODE_POMODORO, "Pomodoro", false);
    }

    //! End the current focus session: save it (if it clears the 10-minute
    //! floor), learn baselines, then ask for a self-rating and show the
    //! summary. Single path for every way a session can end.
    function finishSession(mode as Number, label as String, converted as Boolean) as Void {
        var sm = _sessionManager;
        var engine = _engine;
        var duration = 0;
        var saved = false;
        var timestamp = 0;

        if (sm != null) {
            duration = sm.getSessionDuration();
            if (engine != null) {
                sm.setSessionExtras(engine.getSessionRecord());
            }
            saved = sm.stopSession();
            timestamp = sm.getLastSavedTimestamp();
        }
        var sensors = _sensorManager;
        if (sensors != null) {
            sensors.stopSensors();
        }

        var stats = collectSessionStats(engine, duration, mode, label, converted);
        if (engine != null) {
            if (saved) {
                engine.finalizeSession();
            }
            engine.reset();
        }

        if (!saved) {
            return;
        }

        // Summary first, rating on top: you rate the session *before* seeing
        // the watch's verdict, so its number can't anchor your judgement
        var summaryView = new SessionSummaryView(stats);
        WatchUi.pushView(summaryView, new SessionSummaryDelegate(summaryView), WatchUi.SLIDE_UP);
        WatchUi.pushView(new SelfRatingMenu(),
                         new SelfRatingDelegate(stats, timestamp),
                         WatchUi.SLIDE_IMMEDIATE);
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

        // Cycle stats from the last 4 Pomodoro sessions (newest first)
        var pomoSessions = hm.getTodaySessionsByMode(MODE_POMODORO);
        var count = pomoSessions.size() < 4 ? pomoSessions.size() : 4;
        var cycleSessions = [] as Array<Dictionary>;
        var cycleFocusTime = 0;
        var cycleDeepTime = 0;
        for (var i = 0; i < count; i++) {
            var session = pomoSessions[i];
            cycleSessions.add(session);
            cycleFocusTime += hm.sessionNum(session, "duration", 0);
            cycleDeepTime += hm.sessionNum(session, "deepSec", 0);
        }
        var cycleQuality = hm.avgQuality(cycleSessions);

        var summaryView = new CycleSummaryView(cycleFocusTime, cycleDeepTime,
                                                cycleQuality, completedCycles);
        var summaryDelegate = new CycleSummaryDelegate();
        WatchUi.pushView(summaryView, summaryDelegate, WatchUi.SLIDE_UP);
    }

    function getTimerController() as TimerController? {
        return _timerController;
    }

    function getSensorManager() as SensorManager? {
        return _sensorManager;
    }

    function getEngine() as DeepWorkEngine? {
        return _engine;
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

import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Input handler for the main timer view (dual-mode)
class PomoPulseDelegate extends WatchUi.BehaviorDelegate {

    private var _timerController as TimerController?;
    private var _sensorManager as SensorManager?;
    private var _sessionManager as SessionManager?;
    private var _flowCalculator as FlowScoreCalculator?;
    function initialize(timerController as TimerController?, sensorManager as SensorManager?,
                       sessionManager as SessionManager?, flowCalculator as FlowScoreCalculator?,
                       view as PomoPulseView?) {
        BehaviorDelegate.initialize();
        _timerController = timerController;
        _sensorManager = sensorManager;
        _sessionManager = sessionManager;
        _flowCalculator = flowCalculator;
    }

    //! SELECT button (START/STOP)
    function onSelect() as Boolean {
        var tc = _timerController;
        if (tc == null) { return false; }

        var state = tc.getState();

        if (tc.isFlowtimer()) {
            if (state == STATE_IDLE) {
                tc.start();
                startRecording(MODE_FLOWTIMER);
            } else if (state == STATE_FLOW_RUNNING) {
                tc.pause();
                pauseRecording();
            } else if (state == STATE_FLOW_PAUSED) {
                tc.start();
                resumeRecording();
            }
        } else {
            // Pomodoro mode
            if (state == STATE_IDLE) {
                tc.start();
                startRecording(MODE_POMODORO);
            } else if (state == STATE_POMO_WORK) {
                // No pause allowed in Pomodoro work — ignore
            } else if (state == STATE_POMO_BREAK_WAIT) {
                tc.start();
            } else if (state == STATE_POMO_BREAK) {
                tc.pause();
            }
        }

        WatchUi.requestUpdate();
        return true;
    }

    //! BACK button (LAP/BACK)
    function onBack() as Boolean {
        var tc = _timerController;
        if (tc == null) { return false; }

        var state = tc.getState();

        if (state == STATE_IDLE) {
            return false;  // Exit app
        }

        if (tc.isFlowtimer()) {
            // Stop Flowtimer session
            stopFlowtimerSession();
        } else if (state == STATE_POMO_WORK) {
            // Abandon Pomodoro — confirmation required
            showAbandonConfirmation();
        } else if (tc.isBreakState()) {
            // Stop break, advance to next work
            tc.skipBreak();
        }

        WatchUi.requestUpdate();
        return true;
    }

    //! DOWN button — skip break (Pomodoro only)
    function onNextPage() as Boolean {
        var tc = _timerController;
        if (tc == null) { return false; }

        if (tc.isBreakState()) {
            tc.skipBreak();
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }

    //! UP button (short press) — stats
    function onPreviousPage() as Boolean {
        var statsView = new StatsView(getApp().getHistoryManager());
        var statsDelegate = new StatsDelegate(statsView);
        WatchUi.pushView(statsView, statsDelegate, WatchUi.SLIDE_UP);
        return true;
    }

    //! MENU button (UP long press) — settings
    function onMenu() as Boolean {
        var menu = new SettingsMenu(_timerController);
        var delegate = new SettingsMenuDelegate(_timerController);
        WatchUi.pushView(menu, delegate, WatchUi.SLIDE_UP);
        return true;
    }

    // ── Flowtimer stop ────────────────────────────────────────

    private function stopFlowtimerSession() as Void {
        var tc = _timerController;
        if (tc == null) { return; }

        var activeSeconds = tc.getActiveSeconds();
        tc.resetToIdle();

        if (activeSeconds >= 600) {
            // 10+ minutes — save and show summary
            saveAndShowSummary();
        } else {
            // Too short — discard
            discardRecording();
            tc.vibrate();  // Brief feedback
        }

        if (_flowCalculator != null) {
            _flowCalculator.reset();
        }
    }

    // ── Pomodoro abandon flow ─────────────────────────────────

    private function showAbandonConfirmation() as Void {
        var dialog = new WatchUi.Confirmation("Abandon session?");
        WatchUi.pushView(dialog,
            new AbandonConfirmDelegate(_timerController, _sessionManager,
                                       _sensorManager, _flowCalculator),
            WatchUi.SLIDE_IMMEDIATE);
    }

    // ── Recording lifecycle ───────────────────────────────────

    private function startRecording(mode as Number) as Void {
        var sm = _sessionManager;
        if (sm != null) {
            sm.setSessionMode(mode);
            sm.startSession();
        }
        var sensor = _sensorManager;
        if (sensor != null) {
            sensor.startSensors();
        }
    }

    private function pauseRecording() as Void {
        var sm = _sessionManager;
        if (sm != null) {
            sm.pauseSession();
        }
    }

    private function resumeRecording() as Void {
        var sensor = _sensorManager;
        if (sensor != null && !sensor.areSensorsEnabled()) {
            sensor.startSensors();
        }
        var sm = _sessionManager;
        if (sm != null) {
            sm.resumeSession();
        }
    }

    private function discardRecording() as Void {
        var sm = _sessionManager;
        if (sm != null) {
            sm.discardSession();
        }
        var sensor = _sensorManager;
        if (sensor != null) {
            sensor.stopSensors();
        }
    }

    //! Save session and show summary screen
    private function saveAndShowSummary() as Void {
        var duration = 0;
        var hrvScore = 50;
        var movementScore = 50;
        var mode = MODE_FLOWTIMER;
        var label = "Short flow";
        var converted = false;
        var hasBiometrics = false;

        var sm = _sessionManager;
        if (sm != null) {
            duration = sm.getSessionDuration();
        }

        var fc = _flowCalculator;
        if (fc != null) {
            hrvScore = fc.getHrvScore();
            movementScore = fc.getMovementScore();
            hasBiometrics = fc.hasBiometrics();
        }

        var tc = _timerController;
        if (tc != null) {
            mode = tc.getMode();
            if (mode == MODE_FLOWTIMER) {
                label = tc.getFlowSessionLabelForDuration(duration);
            } else {
                label = "Pomodoro";
            }
        }

        if (sm != null) {
            sm.stopSession();
        }
        if (_sensorManager != null) {
            _sensorManager.stopSensors();
        }

        var summaryView = new SessionSummaryView(duration, hrvScore, movementScore,
                                                  mode, label, converted, hasBiometrics);
        var summaryDelegate = new SessionSummaryDelegate();
        WatchUi.pushView(summaryView, summaryDelegate, WatchUi.SLIDE_UP);
    }

    //! Called by TimerController when work phase completes naturally (Pomodoro)
    function onWorkPhaseComplete() as Void {
        saveAndShowSummary();
    }

    //! Called by TimerController on auto-stop (Flowtimer ceiling/pause timeout)
    function onAutoStop() as Void {
        var tc = _timerController;
        var activeSeconds = 0;
        if (tc != null) {
            activeSeconds = tc.getActiveSeconds();
        }

        if (activeSeconds >= 600) {
            saveAndShowSummary();
        } else {
            discardRecording();
        }

        if (_flowCalculator != null) {
            _flowCalculator.reset();
        }
    }
}

//! Handles the "Abandon session?" confirmation (Pomodoro)
class AbandonConfirmDelegate extends WatchUi.ConfirmationDelegate {

    private var _timerController as TimerController?;
    private var _sessionManager as SessionManager?;
    private var _sensorManager as SensorManager?;
    private var _flowCalculator as FlowScoreCalculator?;

    function initialize(tc as TimerController?, sm as SessionManager?,
                       sensor as SensorManager?, fc as FlowScoreCalculator?) {
        ConfirmationDelegate.initialize();
        _timerController = tc;
        _sessionManager = sm;
        _sensorManager = sensor;
        _flowCalculator = fc;
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            var tc = _timerController;
            var activeSeconds = 0;
            if (tc != null) {
                activeSeconds = tc.getActiveSeconds();
                tc.resetToIdle();
            }

            if (activeSeconds >= 600) {
                // Offer conversion to Flowtimer session
                var dialog = new WatchUi.Confirmation("Save as flow session?");
                WatchUi.pushView(dialog,
                    new ConvertConfirmDelegate(_timerController, _sessionManager,
                                               _sensorManager, _flowCalculator,
                                               activeSeconds),
                    WatchUi.SLIDE_IMMEDIATE);
            } else {
                // Too short — silent discard
                if (_sessionManager != null) {
                    _sessionManager.discardSession();
                }
                if (_sensorManager != null) {
                    _sensorManager.stopSensors();
                }
                if (_flowCalculator != null) {
                    _flowCalculator.reset();
                }
            }
        }
        // CONFIRM_NO — return to running session (do nothing, timer still ticking)
        return true;
    }
}

//! Handles the "Save as flow session?" confirmation (Pomodoro abandon → convert)
class ConvertConfirmDelegate extends WatchUi.ConfirmationDelegate {

    private var _timerController as TimerController?;
    private var _sessionManager as SessionManager?;
    private var _sensorManager as SensorManager?;
    private var _flowCalculator as FlowScoreCalculator?;
    private var _activeSeconds as Number;

    function initialize(tc as TimerController?, sm as SessionManager?,
                       sensor as SensorManager?, fc as FlowScoreCalculator?,
                       activeSeconds as Number) {
        ConfirmationDelegate.initialize();
        _timerController = tc;
        _sessionManager = sm;
        _sensorManager = sensor;
        _flowCalculator = fc;
        _activeSeconds = activeSeconds;
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            // Convert: save as Flowtimer session
            var sm = _sessionManager;
            if (sm != null) {
                sm.setConverted(true);
                sm.setSessionMode(MODE_FLOWTIMER);
                sm.stopSession();
            }
            if (_sensorManager != null) {
                _sensorManager.stopSensors();
            }

            // Show summary
            var hrvScore = 50;
            var movementScore = 50;
            var hasBiometrics = false;
            var fc = _flowCalculator;
            if (fc != null) {
                hrvScore = fc.getHrvScore();
                movementScore = fc.getMovementScore();
                hasBiometrics = fc.hasBiometrics();
                fc.reset();
            }

            var tc = _timerController;
            var label = "Short flow";
            if (tc != null) {
                label = tc.getFlowSessionLabelForDuration(_activeSeconds);
            }

            var summaryView = new SessionSummaryView(_activeSeconds, hrvScore, movementScore,
                                                      MODE_FLOWTIMER, label, true, hasBiometrics);
            var summaryDelegate = new SessionSummaryDelegate();
            WatchUi.pushView(summaryView, summaryDelegate, WatchUi.SLIDE_UP);
        } else {
            // Discard entirely
            if (_sessionManager != null) {
                _sessionManager.discardSession();
            }
            if (_sensorManager != null) {
                _sensorManager.stopSensors();
            }
            if (_flowCalculator != null) {
                _flowCalculator.reset();
            }
        }
        return true;
    }
}

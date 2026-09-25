import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Input handler for the main timer view (dual-mode)
class PomoPulseDelegate extends WatchUi.BehaviorDelegate {

    private var _timerController as TimerController?;
    private var _sensorManager as SensorManager?;
    private var _sessionManager as SessionManager?;
    private var _engine as DeepWorkEngine?;
    function initialize(timerController as TimerController?, sensorManager as SensorManager?,
                       sessionManager as SessionManager?, engine as DeepWorkEngine?,
                       view as PomoPulseView?) {
        BehaviorDelegate.initialize();
        _timerController = timerController;
        _sensorManager = sensorManager;
        _sessionManager = sessionManager;
        _engine = engine;
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

    //! DOWN button — during focus: log "I got distracted";
    //! during a Pomodoro break: skip the break
    function onNextPage() as Boolean {
        var tc = _timerController;
        if (tc == null) { return false; }

        var state = tc.getState();
        if (state == STATE_FLOW_RUNNING || state == STATE_POMO_WORK) {
            var engine = _engine;
            if (engine != null) {
                engine.logDistraction();
                tc.vibrateTick();
                WatchUi.requestUpdate();
            }
            return true;
        }

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

        var engine = _engine;
        if (engine != null) {
            engine.reset();
        }
    }

    // ── Pomodoro abandon flow ─────────────────────────────────

    private function showAbandonConfirmation() as Void {
        var dialog = new WatchUi.Confirmation("Abandon session?");
        WatchUi.pushView(dialog,
            new AbandonConfirmDelegate(_timerController, _sessionManager,
                                       _sensorManager, _engine),
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
        var sensor = _sensorManager;
        if (sensor != null) {
            sensor.setPaused(true);
        }
    }

    private function resumeRecording() as Void {
        var sensor = _sensorManager;
        if (sensor != null) {
            if (!sensor.areSensorsEnabled()) {
                sensor.startSensors();
            }
            sensor.setPaused(false);
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

    //! Save the Flowtimer session and show rating + summary
    private function saveAndShowSummary() as Void {
        var duration = 0;
        var sm = _sessionManager;
        if (sm != null) {
            duration = sm.getSessionDuration();
        }
        var label = "Short flow";
        var tc = _timerController;
        if (tc != null) {
            label = tc.getFlowSessionLabelForDuration(duration);
        }
        getApp().finishSession(MODE_FLOWTIMER, label, false);
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

        var engine = _engine;
        if (engine != null) {
            engine.reset();
        }
    }
}

//! Handles the "Abandon session?" confirmation (Pomodoro)
class AbandonConfirmDelegate extends WatchUi.ConfirmationDelegate {

    private var _timerController as TimerController?;
    private var _sessionManager as SessionManager?;
    private var _sensorManager as SensorManager?;
    private var _engine as DeepWorkEngine?;

    function initialize(tc as TimerController?, sm as SessionManager?,
                       sensor as SensorManager?, fc as DeepWorkEngine?) {
        ConfirmationDelegate.initialize();
        _timerController = tc;
        _sessionManager = sm;
        _sensorManager = sensor;
        _engine = fc;
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
                                               _sensorManager, _engine,
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
                var engine = _engine;
                if (engine != null) {
                    engine.reset();
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
    private var _engine as DeepWorkEngine?;
    private var _activeSeconds as Number;

    function initialize(tc as TimerController?, sm as SessionManager?,
                       sensor as SensorManager?, fc as DeepWorkEngine?,
                       activeSeconds as Number) {
        ConfirmationDelegate.initialize();
        _timerController = tc;
        _sessionManager = sm;
        _sensorManager = sensor;
        _engine = fc;
        _activeSeconds = activeSeconds;
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            // Convert: save as Flowtimer session
            var sm = _sessionManager;
            if (sm != null) {
                sm.setConverted(true);
                sm.setSessionMode(MODE_FLOWTIMER);
            }
            var tc = _timerController;
            var label = "Short flow";
            if (tc != null) {
                label = tc.getFlowSessionLabelForDuration(_activeSeconds);
            }
            getApp().finishSession(MODE_FLOWTIMER, label, true);
        } else {
            // Discard entirely
            if (_sessionManager != null) {
                _sessionManager.discardSession();
            }
            if (_sensorManager != null) {
                _sensorManager.stopSensors();
            }
            var engine = _engine;
            if (engine != null) {
                engine.reset();
            }
        }
        return true;
    }
}

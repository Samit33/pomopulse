import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Main timer display — dual-mode (Flowtimer / Pomodoro).
//! Biometric data is recorded silently; insights surfaced post-session.
class PomoPulseView extends WatchUi.View {

    private var _timerController as TimerController?;
    private var _flowCalculator  as FlowScoreCalculator?;
    private var _sensorManager   as SensorManager?;
    private var _sessionManager  as SessionManager?;

    private var _screenWidth  as Number = 0;
    private var _screenHeight as Number = 0;
    private var _centerX      as Number = 0;
    private var _centerY      as Number = 0;

    // Colors
    private const COLOR_FLOW    = 0x44DDAA;  // Teal (Flowtimer)
    private const COLOR_WORK    = 0x4488FF;  // Blue (Pomodoro work)
    private const COLOR_BREAK   = 0x44DDAA;  // Teal (Pomodoro break)
    private const COLOR_PAUSED  = 0x888888;  // Gray
    private const COLOR_BG      = 0x000000;
    private const COLOR_TEXT    = 0xFFFFFF;
    private const COLOR_TEXT_DIM = 0xAAAAAA;

    function initialize(timerController as TimerController?, flowCalculator as FlowScoreCalculator?,
                       sensorManager as SensorManager?, sessionManager as SessionManager?) {
        View.initialize();
        _timerController = timerController;
        _flowCalculator  = flowCalculator;
        _sensorManager   = sensorManager;
        _sessionManager  = sessionManager;
        var settings = System.getDeviceSettings();
        _screenWidth  = settings.screenWidth;
        _screenHeight = settings.screenHeight;
        _centerX = _screenWidth  / 2;
        _centerY = _screenHeight / 2;
    }

    function onLayout(dc as Dc) as Void {
        _screenWidth  = dc.getWidth();
        _screenHeight = dc.getHeight();
        _centerX = _screenWidth  / 2;
        _centerY = _screenHeight / 2;
    }

    function onShow() as Void {
        if (_timerController != null) {
            _timerController.setTickCallback(method(:onTimerTick));
        }
    }

    function onHide() as Void {
        if (_timerController != null) {
            _timerController.setTickCallback(null);
        }
    }

    //! Called every second — records flow score silently
    function onTimerTick() as Void {
        var tc = _timerController;
        var fc = _flowCalculator;
        var sm = _sessionManager;
        if (tc != null && tc.isWorkState() && tc.isRunning() && fc != null && sm != null) {
            sm.recordFlowScore(fc.getFlowScore());
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        var tc = _timerController;
        if (tc == null) {
            return;
        }

        if (tc.isBreakState()) {
            drawBreakScreen(dc);
        } else if (tc.isFlowtimer()) {
            drawFlowScreen(dc);
        } else {
            drawPomoScreen(dc);
        }
    }

    // ── Flowtimer screens ─────────────────────────────────────

    private function drawFlowScreen(dc as Dc) as Void {
        var tc = _timerController;
        if (tc == null) { return; }

        var state = tc.getState();

        // Mode label at top
        dc.setColor(COLOR_FLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 28, Graphics.FONT_TINY, "FLOW", Graphics.TEXT_JUSTIFY_CENTER);

        // Timer (hero)
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY - 15, Graphics.FONT_NUMBER_HOT,
                    tc.getDisplayTimeString(), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (state == STATE_IDLE) {
            // Ready state
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, _centerY + 25, Graphics.FONT_SMALL,
                        "Ready", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(_centerX, _screenHeight - 45, Graphics.FONT_TINY,
                        "Press START", Graphics.TEXT_JUSTIFY_CENTER);

        } else if (state == STATE_FLOW_RUNNING) {
            // Flow label (Short/Deep/Extended)
            dc.setColor(COLOR_FLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, _centerY + 25, Graphics.FONT_SMALL,
                        tc.getFlowSessionLabel(), Graphics.TEXT_JUSTIFY_CENTER);

            // HR at bottom
            drawSensorInfo(dc);

        } else if (state == STATE_FLOW_PAUSED) {
            // Paused label
            dc.setColor(COLOR_PAUSED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, _centerY + 25, Graphics.FONT_SMALL,
                        "Paused", Graphics.TEXT_JUSTIFY_CENTER);

            // Pause timeout countdown
            var pauseRemaining = tc.getPauseRemainingSeconds();
            var pauseMin = pauseRemaining / 60;
            var pauseSec = pauseRemaining % 60;
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, _centerY + 55, Graphics.FONT_XTINY,
                        "Auto-ends in " + pauseMin.format("%d") + ":" + pauseSec.format("%02d"),
                        Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // ── Pomodoro screens ──────────────────────────────────────

    private function drawPomoScreen(dc as Dc) as Void {
        var tc = _timerController;
        if (tc == null) { return; }

        var state = tc.getState();

        // Progress arc
        drawProgressArc(dc);

        // Pomodoro dots
        drawPomodoroCount(dc);

        // Timer (countdown)
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY - 15, Graphics.FONT_NUMBER_HOT,
                    tc.getDisplayTimeString(), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (state == STATE_IDLE) {
            // Cycle position
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, _centerY + 25, Graphics.FONT_SMALL,
                        "Session " + tc.getCyclePosition() + " of 4",
                        Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(_centerX, _screenHeight - 45, Graphics.FONT_TINY,
                        "Press START", Graphics.TEXT_JUSTIFY_CENTER);

        } else if (state == STATE_POMO_WORK) {
            // Cycle position label
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, _centerY + 25, Graphics.FONT_XTINY,
                        "Pomodoro " + tc.getCyclePosition() + " of 4",
                        Graphics.TEXT_JUSTIFY_CENTER);

            // HR at bottom
            drawSensorInfo(dc);
        }
    }

    // ── Break screen (Pomodoro only) ──────────────────────────

    private function drawBreakScreen(dc as Dc) as Void {
        var tc = _timerController;
        if (tc == null) { return; }

        drawProgressArc(dc);
        drawPomodoroCount(dc);

        // Timer
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY - 15, Graphics.FONT_NUMBER_HOT,
                    tc.getDisplayTimeString(), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Break type label
        var breakLabel = tc.isLongBreak() ? "Long Break" : "Short Break";
        dc.setColor(COLOR_BREAK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY + 20, Graphics.FONT_SMALL,
                    breakLabel, Graphics.TEXT_JUSTIFY_CENTER);

        // Completion note
        var count = tc.getPomodorosCompleted();
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY + 52, Graphics.FONT_XTINY,
                    "#" + count.format("%d") + " done - Rest up!",
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Press START hint when break is waiting
        if (tc.getState() == STATE_POMO_BREAK_WAIT) {
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, _screenHeight - 45, Graphics.FONT_TINY,
                        "Press START", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // ── Shared drawing helpers ────────────────────────────────

    //! Progress arc (Pomodoro only)
    private function drawProgressArc(dc as Dc) as Void {
        var tc = _timerController;
        if (tc == null) { return; }
        var progress = tc.getProgress();
        var arcColor;

        if (tc.getState() == STATE_POMO_BREAK) {
            arcColor = COLOR_BREAK;
        } else if (tc.getState() == STATE_POMO_BREAK_WAIT) {
            arcColor = COLOR_PAUSED;
        } else if (tc.isRunning()) {
            arcColor = COLOR_WORK;
        } else {
            arcColor = COLOR_PAUSED;
        }

        // Background arc
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(8);
        dc.drawArc(_centerX, _centerY, _centerX - 10, Graphics.ARC_CLOCKWISE, 90, -270);

        // Progress arc
        if (progress > 0) {
            dc.setColor(arcColor, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(8);
            var endAngle = 90 - ((progress * 360) / 100);
            dc.drawArc(_centerX, _centerY, _centerX - 10, Graphics.ARC_CLOCKWISE, 90, endAngle);
        }
    }

    //! Pomodoro count dots
    private function drawPomodoroCount(dc as Dc) as Void {
        var tc = _timerController;
        if (tc == null) { return; }
        var count = tc.getPomodorosCompleted();

        var displayCount = count > 4 ? 4 : count;
        var startX = _centerX - ((displayCount - 1) * 12) / 2;

        dc.setColor(0xFF6B6B, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < displayCount; i++) {
            dc.fillCircle(startX + (i * 12), 30, 4);
        }

        if (count > 4) {
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX + 35, 25, Graphics.FONT_TINY,
                        "+" + (count - 4).format("%d"), Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    //! HR readout at bottom
    private function drawSensorInfo(dc as Dc) as Void {
        if (_sensorManager == null) { return; }
        var hr = _sensorManager.getHeartRate();
        var hrText = hr > 0 ? hr.format("%d") + " bpm" : "-- bpm";
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _screenHeight - 45, Graphics.FONT_TINY,
                    hrText, Graphics.TEXT_JUSTIFY_CENTER);
    }
}

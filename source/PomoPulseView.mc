import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

//! Main timer display — dual-mode (Flowtimer / Pomodoro).
//! Shows a discreet live flow-zone indicator during focus (no distracting
//! numbers); full insights are surfaced post-session.
class PomoPulseView extends WatchUi.View {

    private var _timerController as TimerController?;
    private var _flowCalculator  as FlowScoreCalculator?;
    private var _sensorManager   as SensorManager?;
    private var _sessionManager  as SessionManager?;

    private var _screenWidth  as Number = 0;
    private var _screenHeight as Number = 0;
    private var _centerX      as Number = 0;
    private var _centerY      as Number = 0;

    // Whether the live zone indicator is enabled (Settings > Live Flow)
    private var _liveFlowEnabled as Boolean = true;

    // Colors
    private const COLOR_FLOW     = 0x44DDAA;  // Teal (flow zone / Flowtimer)
    private const COLOR_WORK     = 0x4488FF;  // Blue (focused zone / Pomodoro work)
    private const COLOR_BUILD    = 0xFFAA00;  // Amber (building zone)
    private const COLOR_PAUSED   = 0x888888;  // Gray
    private const COLOR_BG       = 0x000000;
    private const COLOR_TEXT     = 0xFFFFFF;
    private const COLOR_TEXT_DIM = 0xAAAAAA;
    private const COLOR_RING_BG  = 0x222222;
    private const COLOR_INACTIVE = 0x444444;

    // Flowtimer ring spans the 120-min ceiling with milestone ticks
    private const FLOW_RING_TOTAL_SECONDS = 120 * 60;

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
        _liveFlowEnabled = isLiveFlowEnabled();
    }

    function onHide() as Void {
        if (_timerController != null) {
            _timerController.setTickCallback(null);
        }
    }

    //! Called every second — flow scores are recorded at app level,
    //! this only refreshes the display.
    function onTimerTick() as Void {
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

        // Session ring: elapsed progress through the 120-min ceiling,
        // with milestone ticks at 25 / 60 / 90 min
        drawFlowRing(dc, tc.getActiveSeconds(), state == STATE_FLOW_PAUSED);

        // Mode label at top
        dc.setColor(state == STATE_FLOW_PAUSED ? COLOR_PAUSED : COLOR_FLOW,
                    Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 26, Graphics.FONT_TINY, "FLOW", Graphics.TEXT_JUSTIFY_CENTER);

        // Timer (hero)
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY - 15, Graphics.FONT_NUMBER_HOT,
                    tc.getDisplayTimeString(), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (state == STATE_IDLE) {
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, _centerY + 25, Graphics.FONT_SMALL,
                        "Ready", Graphics.TEXT_JUSTIFY_CENTER);
            drawTodayTeaser(dc, _centerY + 55);
            dc.drawText(_centerX, _screenHeight - 45, Graphics.FONT_TINY,
                        "Press START", Graphics.TEXT_JUSTIFY_CENTER);

        } else if (state == STATE_FLOW_RUNNING) {
            // Flow label (Short/Deep/Extended)
            dc.setColor(COLOR_FLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, _centerY + 25, Graphics.FONT_SMALL,
                        tc.getFlowSessionLabel(), Graphics.TEXT_JUSTIFY_CENTER);

            drawLiveZoneIndicator(dc);
            drawSensorInfo(dc);

        } else if (state == STATE_FLOW_PAUSED) {
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

    //! Ring around the Flowtimer screen filling toward the 120-min ceiling
    private function drawFlowRing(dc as Dc, activeSeconds as Number, paused as Boolean) as Void {
        var radius = _centerX - 8;

        // Background ring
        dc.setColor(COLOR_RING_BG, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(5);
        dc.drawArc(_centerX, _centerY, radius, Graphics.ARC_CLOCKWISE, 90, -270);

        // Elapsed arc
        var progress = (activeSeconds * 360) / FLOW_RING_TOTAL_SECONDS;
        if (progress > 360) { progress = 360; }
        if (progress > 0) {
            dc.setColor(paused ? COLOR_PAUSED : COLOR_FLOW, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(5);
            dc.drawArc(_centerX, _centerY, radius, Graphics.ARC_CLOCKWISE, 90, 90 - progress);
        }

        // Milestone ticks: 25 min (deep), 60 min (extended), 90 min (nudge)
        drawMilestoneTick(dc, radius, 25 * 60, activeSeconds);
        drawMilestoneTick(dc, radius, 60 * 60, activeSeconds);
        drawMilestoneTick(dc, radius, 90 * 60, activeSeconds);
    }

    private function drawMilestoneTick(dc as Dc, radius as Number,
                                       milestoneSeconds as Number,
                                       activeSeconds as Number) as Void {
        var angleDeg = 90.0 - ((milestoneSeconds.toFloat() / FLOW_RING_TOTAL_SECONDS) * 360.0);
        var angleRad = angleDeg * Math.PI / 180.0;
        var x = _centerX + (radius * Math.cos(angleRad));
        var y = _centerY - (radius * Math.sin(angleRad));

        var reached = activeSeconds >= milestoneSeconds;
        dc.setColor(reached ? COLOR_FLOW : COLOR_INACTIVE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x.toNumber(), y.toNumber(), 3);
    }

    // ── Pomodoro screens ──────────────────────────────────────

    private function drawPomoScreen(dc as Dc) as Void {
        var tc = _timerController;
        if (tc == null) { return; }

        var state = tc.getState();

        drawProgressArc(dc);
        drawCycleDots(dc);

        // Timer (countdown)
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY - 15, Graphics.FONT_NUMBER_HOT,
                    tc.getDisplayTimeString(), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (state == STATE_IDLE) {
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, _centerY + 25, Graphics.FONT_SMALL,
                        "Focus " + tc.getCyclePosition() + " of 4",
                        Graphics.TEXT_JUSTIFY_CENTER);
            drawTodayTeaser(dc, _centerY + 55);
            dc.drawText(_centerX, _screenHeight - 45, Graphics.FONT_TINY,
                        "Press START", Graphics.TEXT_JUSTIFY_CENTER);

        } else if (state == STATE_POMO_WORK) {
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, _centerY + 25, Graphics.FONT_XTINY,
                        "Focus " + tc.getCyclePosition() + " of 4",
                        Graphics.TEXT_JUSTIFY_CENTER);

            drawLiveZoneIndicator(dc);
            drawSensorInfo(dc);
        }
    }

    // ── Break screen (Pomodoro only) ──────────────────────────

    private function drawBreakScreen(dc as Dc) as Void {
        var tc = _timerController;
        if (tc == null) { return; }

        drawProgressArc(dc);
        drawCycleDots(dc);

        // Timer
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY - 15, Graphics.FONT_NUMBER_HOT,
                    tc.getDisplayTimeString(), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Break type label
        var breakLabel = tc.isLongBreak() ? "Long Break" : "Short Break";
        dc.setColor(COLOR_FLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY + 20, Graphics.FONT_SMALL,
                    breakLabel, Graphics.TEXT_JUSTIFY_CENTER);

        // What comes next
        var cyclePos = tc.getCyclePosition();
        var next = cyclePos >= 4 ? 1 : cyclePos + 1;
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY + 52, Graphics.FONT_XTINY,
                    "Next: Focus " + next.format("%d") + " of 4",
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Press START hint when break is waiting
        if (tc.getState() == STATE_POMO_BREAK_WAIT) {
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, _screenHeight - 45, Graphics.FONT_TINY,
                        "Press START", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // ── Shared drawing helpers ────────────────────────────────

    //! Progress arc (Pomodoro phases)
    private function drawProgressArc(dc as Dc) as Void {
        var tc = _timerController;
        if (tc == null) { return; }
        var progress = tc.getProgress();
        var arcColor;

        if (tc.getState() == STATE_POMO_BREAK) {
            arcColor = COLOR_FLOW;
        } else if (tc.getState() == STATE_POMO_BREAK_WAIT) {
            arcColor = COLOR_PAUSED;
        } else if (tc.isRunning()) {
            arcColor = COLOR_WORK;
        } else {
            arcColor = COLOR_PAUSED;
        }

        // Background arc
        dc.setColor(COLOR_RING_BG, Graphics.COLOR_TRANSPARENT);
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

    //! Cycle position dots: 4 fixed slots — filled = done this cycle,
    //! ring = current session, dim = upcoming
    private function drawCycleDots(dc as Dc) as Void {
        var tc = _timerController;
        if (tc == null) { return; }

        var cyclePos = tc.getCyclePosition();
        // During a break the current session is already finished
        var completed = tc.isBreakState() ? cyclePos : cyclePos - 1;

        var spacing = 18;
        var startX = _centerX - ((3 * spacing) / 2);
        var y = 32;

        for (var i = 0; i < 4; i++) {
            var x = startX + (i * spacing);
            if (i < completed) {
                dc.setColor(COLOR_FLOW, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, 4);
            } else if (i == completed && !tc.isBreakState()) {
                dc.setColor(COLOR_WORK, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(2);
                dc.drawCircle(x, y, 4);
            } else {
                dc.setColor(COLOR_INACTIVE, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(1);
                dc.drawCircle(x, y, 3);
            }
        }
    }

    //! Discreet live zone indicator: three dots (building / focused / flow).
    //! No numbers — just a hint of where you are. Hidden during the sensor
    //! warm-up minute and when disabled in settings.
    private function drawLiveZoneIndicator(dc as Dc) as Void {
        if (!_liveFlowEnabled) { return; }
        var fc = _flowCalculator;
        if (fc == null) { return; }

        var zone = fc.getCurrentZone();
        var y = _screenHeight - 68;
        var spacing = 16;

        var colors = [COLOR_BUILD, COLOR_WORK, COLOR_FLOW] as Array<Number>;
        for (var i = 0; i < 3; i++) {
            var x = _centerX + ((i - 1) * spacing);
            // zone 1..3 maps to dot 0..2; warm-up (0) lights nothing
            if (zone == i + 1) {
                dc.setColor(colors[i], Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, 5);
            } else {
                dc.setColor(COLOR_INACTIVE, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, 2);
            }
        }
    }

    //! Total focus time recorded today (idle screens only)
    private function drawTodayTeaser(dc as Dc, y as Number) as Void {
        var hm = getApp().getHistoryManager();
        if (hm == null) { return; }
        var todayTime = hm.getTodayFocusTime();
        if (todayTime <= 0) { return; }
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, y, Graphics.FONT_XTINY,
                    "Today: " + hm.formatDurationCompact(todayTime),
                    Graphics.TEXT_JUSTIFY_CENTER);
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

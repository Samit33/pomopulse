import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Main timer display — clean Pomodoro timer with quiet HR readout.
//! Biometric data is recorded silently in the background; insights are
//! surfaced in the post-session summary and stats screens, not here.
class PomoPulseView extends WatchUi.View {

    private var _timerController as TimerController?;
    private var _flowCalculator  as FlowScoreCalculator?;
    private var _sensorManager   as SensorManager?;
    private var _sessionManager  as SessionManager?;

    // Screen dimensions
    private var _screenWidth  as Number = 0;
    private var _screenHeight as Number = 0;
    private var _centerX      as Number = 0;
    private var _centerY      as Number = 0;

    // Colors
    private const COLOR_WORK    = 0x4488FF;  // Blue
    private const COLOR_BREAK   = 0x44DDAA;  // Teal
    private const COLOR_PAUSED  = 0x888888;  // Gray
    private const COLOR_BG      = 0x000000;  // Black
    private const COLOR_TEXT    = 0xFFFFFF;  // White
    private const COLOR_TEXT_DIM = 0xAAAAAA; // Dim gray

    //! Constructor
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

    //! Load resources
    function onLayout(dc as Dc) as Void {
        _screenWidth  = dc.getWidth();
        _screenHeight = dc.getHeight();
        _centerX = _screenWidth  / 2;
        _centerY = _screenHeight / 2;
    }

    //! Called when this View is brought to the foreground
    function onShow() as Void {
        if (_timerController != null) {
            _timerController.setCallback(method(:onTimerTick));
        }
    }

    //! Called when this View is removed from the screen
    function onHide() as Void {
        if (_timerController != null) {
            _timerController.setCallback(null);
        }
    }

    //! Called every second when timer is running — records flow score silently
    function onTimerTick() as Void {
        var tc = _timerController;
        var fc = _flowCalculator;
        var sm = _sessionManager;
        if (tc != null && tc.isRunning() && tc.isWorkState() && fc != null && sm != null) {
            sm.recordFlowScore(fc.getFlowScore());
        }
        WatchUi.requestUpdate();
    }

    //! Update the view
    function onUpdate(dc as Dc) as Void {
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        if (_timerController == null) {
            return;
        }

        var tc = _timerController;
        if (tc.isBreakState()) {
            drawBreakScreen(dc);
        } else {
            drawWorkScreen(dc);
        }
    }

    //! Draw the work/idle screen — timer is the hero, HR shown quietly below
    private function drawWorkScreen(dc as Dc) as Void {
        drawProgressArc(dc);
        drawPomodoroCount(dc);
        drawTimer(dc);

        var tc = _timerController;
        if (tc != null && !tc.isRunning()) {
            drawStateLabel(dc);
        }

        drawSensorInfo(dc);
    }

    //! Draw break screen — countdown + break type label, no biometric data
    private function drawBreakScreen(dc as Dc) as Void {
        drawProgressArc(dc);
        drawPomodoroCount(dc);
        drawTimer(dc);
        drawBreakTypeLabel(dc);
        drawBreakCompletionNote(dc);
    }

    //! Draw "Short Break" or "Long Break" label
    private function drawBreakTypeLabel(dc as Dc) as Void {
        var tc = _timerController;
        if (tc == null) { return; }
        var label = tc.isLongBreak() ? "Long Break" : "Short Break";
        dc.setColor(COLOR_BREAK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY + 20, Graphics.FONT_SMALL,
                    label, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Show which pomodoro was just completed
    private function drawBreakCompletionNote(dc as Dc) as Void {
        var tc = _timerController;
        if (tc == null) { return; }
        var count = tc.getPomodorosCompleted();
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY + 52, Graphics.FONT_XTINY,
                    "#" + count.format("%d") + " done - Rest up!",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Draw the circular progress arc.
    //! Colored by phase (blue = work, teal = break, gray = paused).
    private function drawProgressArc(dc as Dc) as Void {
        var tc = _timerController;
        if (tc == null) { return; }
        var progress = tc.getProgress();
        var arcColor;

        if (tc.isBreakState()) {
            arcColor = COLOR_BREAK;
        } else if (tc.isRunning()) {
            arcColor = COLOR_WORK;
        } else {
            arcColor = COLOR_PAUSED;
        }

        // Background arc (full circle, dimmed)
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

    //! Draw the main timer — always large, centered
    private function drawTimer(dc as Dc) as Void {
        var tc = _timerController;
        if (tc == null) { return; }
        var timeString = tc.getRemainingTimeString();
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY - 15, Graphics.FONT_NUMBER_HOT,
                    timeString, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Draw the state label (shown when timer is paused or idle)
    private function drawStateLabel(dc as Dc) as Void {
        var tc = _timerController;
        if (tc == null) { return; }
        var stateLabel = tc.getStateLabel();
        dc.setColor(COLOR_PAUSED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY + 20, Graphics.FONT_SMALL,
                    stateLabel, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Draw HR as a small, quiet number at the bottom — no color coding
    private function drawSensorInfo(dc as Dc) as Void {
        if (_sensorManager == null) { return; }
        var hr = _sensorManager.getHeartRate();
        var hrText = hr > 0 ? hr.format("%d") + " bpm" : "-- bpm";
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _screenHeight - 45, Graphics.FONT_TINY,
                    hrText, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Draw pomodoro count as dots at the top
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
}

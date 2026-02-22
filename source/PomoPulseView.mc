import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Main timer display view with Flow Score gauge
class PomoPulseView extends WatchUi.View {

    private var _timerController as TimerController?;
    private var _flowCalculator as FlowScoreCalculator?;
    private var _sensorManager as SensorManager?;
    private var _sessionManager as SessionManager?;

    // Screen dimensions
    private var _screenWidth as Number = 0;
    private var _screenHeight as Number = 0;
    private var _centerX as Number = 0;
    private var _centerY as Number = 0;

    // Colors
    private const COLOR_FLOW_LOW = 0xFF4444;      // Red
    private const COLOR_FLOW_MED = 0xFFAA00;      // Yellow/Orange
    private const COLOR_FLOW_HIGH = 0x44FF44;     // Green
    private const COLOR_WORK = 0x4488FF;          // Blue
    private const COLOR_BREAK = 0x44DDAA;         // Teal
    private const COLOR_PAUSED = 0x888888;        // Gray
    private const COLOR_BG = 0x000000;            // Black
    private const COLOR_TEXT = 0xFFFFFF;          // White
    private const COLOR_TEXT_DIM = 0xAAAAAA;      // Gray

    //! Constructor
    function initialize(timerController as TimerController?, flowCalculator as FlowScoreCalculator?,
                       sensorManager as SensorManager?, sessionManager as SessionManager?) {
        View.initialize();
        _timerController = timerController;
        _flowCalculator = flowCalculator;
        _sensorManager = sensorManager;
        _sessionManager = sessionManager;
        // Initialize screen dimensions eagerly so onUpdate is safe before onLayout fires
        var settings = System.getDeviceSettings();
        _screenWidth = settings.screenWidth;
        _screenHeight = settings.screenHeight;
        _centerX = _screenWidth / 2;
        _centerY = _screenHeight / 2;
    }

    //! Load resources
    function onLayout(dc as Dc) as Void {
        _screenWidth = dc.getWidth();
        _screenHeight = dc.getHeight();
        _centerX = _screenWidth / 2;
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

    //! Called every second when timer is running
    function onTimerTick() as Void {
        // Record flow score to FIT file during work sessions
        var tc = _timerController;
        var fc = _flowCalculator;
        var sm = _sessionManager;
        if (tc != null && tc.isRunning() && tc.isWorkState() && fc != null && sm != null) {
            sm.recordFlowScore(fc.getFlowScore());
        }

        // Update UI
        WatchUi.requestUpdate();
    }

    //! Update the view
    function onUpdate(dc as Dc) as Void {
        // Clear screen
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        if (_timerController == null) {
            return;
        }

        // Draw components
        drawProgressArc(dc);
        drawFlowScoreGauge(dc);
        drawTimer(dc);
        drawStateLabel(dc);
        drawSensorInfo(dc);
        drawPomodoroCount(dc);
    }

    //! Draw the circular progress arc
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
            var endAngle = 90 - ((progress * 360) / 100);
            dc.drawArc(_centerX, _centerY, _centerX - 10, Graphics.ARC_CLOCKWISE, 90, endAngle);
        }
    }

    //! Draw the Flow Score gauge on the right side
    private function drawFlowScoreGauge(dc as Dc) as Void {
        if (_flowCalculator == null) {
            return;
        }

        var flowScore = _flowCalculator.getFlowScore();
        var gaugeX = _screenWidth - 35;
        var gaugeTop = _centerY - 50;
        var gaugeHeight = 100;
        var gaugeWidth = 12;

        // Background
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(gaugeX, gaugeTop, gaugeWidth, gaugeHeight);

        // Flow level fill
        var fillHeight = (flowScore * gaugeHeight) / 100;
        var fillY = gaugeTop + gaugeHeight - fillHeight;
        var fillColor = getFlowColor(flowScore);

        dc.setColor(fillColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(gaugeX, fillY, gaugeWidth, fillHeight);

        // Border
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(gaugeX, gaugeTop, gaugeWidth, gaugeHeight);

        // Score label
        dc.setColor(fillColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(gaugeX + gaugeWidth / 2, gaugeTop - 20, Graphics.FONT_TINY,
                    flowScore.toString(), Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Get color based on flow score
    private function getFlowColor(score as Number) as Number {
        if (score < 40) {
            return COLOR_FLOW_LOW;
        } else if (score < 70) {
            return COLOR_FLOW_MED;
        } else {
            return COLOR_FLOW_HIGH;
        }
    }

    //! Draw the main timer display
    private function drawTimer(dc as Dc) as Void {
        var tc = _timerController;
        if (tc == null) { return; }
        var timeString = tc.getRemainingTimeString();

        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY - 25, Graphics.FONT_NUMBER_HOT,
                    timeString, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Draw the state label
    private function drawStateLabel(dc as Dc) as Void {
        var tc = _timerController;
        if (tc == null) { return; }
        var stateLabel = tc.getStateLabel();
        var stateColor;

        if (tc.isBreakState()) {
            stateColor = COLOR_BREAK;
        } else if (tc.isRunning()) {
            stateColor = COLOR_WORK;
        } else {
            stateColor = COLOR_PAUSED;
        }

        dc.setColor(stateColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY + 35, Graphics.FONT_SMALL,
                    stateLabel, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Draw sensor information (HR primarily)
    private function drawSensorInfo(dc as Dc) as Void {
        if (_sensorManager == null) {
            return;
        }

        var hr = _sensorManager.getHeartRate();
        var hrText = hr > 0 ? hr.format("%d") + " bpm" : "-- bpm";

        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _screenHeight - 45, Graphics.FONT_TINY,
                    hrText, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Draw pomodoro count
    private function drawPomodoroCount(dc as Dc) as Void {
        var tc = _timerController;
        if (tc == null) { return; }
        var count = tc.getPomodorosCompleted();

        // Draw filled circles for completed pomodoros (max 4 displayed)
        var displayCount = count > 4 ? 4 : count;
        var startX = _centerX - ((displayCount - 1) * 12) / 2;

        dc.setColor(0xFF6B6B, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < displayCount; i++) {
            dc.fillCircle(startX + (i * 12), 30, 4);
        }

        // Show count if more than 4
        if (count > 4) {
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX + 35, 25, Graphics.FONT_TINY,
                        "+" + (count - 4).format("%d"), Graphics.TEXT_JUSTIFY_LEFT);
        }
    }
}

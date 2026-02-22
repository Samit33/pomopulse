import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Main timer display view with Flow Score as the hero element
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
    private const COLOR_FLOW_HIGH = 0x44FF44;      // Green
    private const COLOR_WORK = 0x4488FF;           // Blue
    private const COLOR_BREAK = 0x44DDAA;          // Teal
    private const COLOR_PAUSED = 0x888888;         // Gray
    private const COLOR_BG = 0x000000;             // Black
    private const COLOR_TEXT = 0xFFFFFF;           // White
    private const COLOR_TEXT_DIM = 0xAAAAAA;       // Gray
    private const COLOR_WARMUP = 0x5566AA;         // Muted blue for warm-up

    //! Constructor
    function initialize(timerController as TimerController?, flowCalculator as FlowScoreCalculator?,
                       sensorManager as SensorManager?, sessionManager as SessionManager?) {
        View.initialize();
        _timerController = timerController;
        _flowCalculator = flowCalculator;
        _sensorManager = sensorManager;
        _sessionManager = sessionManager;
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

    //! Draw the work/idle screen with flow score as hero
    private function drawWorkScreen(dc as Dc) as Void {
        drawProgressArc(dc);
        drawPomodoroCount(dc);
        drawTimer(dc);

        var tc = _timerController;
        if (tc != null && tc.isRunning() && _flowCalculator != null) {
            if (!_flowCalculator.isWarmedUp()) {
                drawWarmupIndicator(dc);
            } else {
                drawFlowScore(dc);
                drawFlowZoneLabel(dc);
                drawTrendArrow(dc);
            }
        } else {
            drawStateLabel(dc);
        }

        drawSensorInfo(dc);
    }

    //! Draw break screen with session summary instead of flow gauge
    private function drawBreakScreen(dc as Dc) as Void {
        drawProgressArc(dc);
        drawPomodoroCount(dc);
        drawTimer(dc);
        drawStateLabel(dc);
        drawBreakSessionSummary(dc);
    }

    //! Draw the circular progress arc, colored by flow state during work
    private function drawProgressArc(dc as Dc) as Void {
        var tc = _timerController;
        if (tc == null) { return; }
        var progress = tc.getProgress();
        var arcColor;

        if (tc.isBreakState()) {
            arcColor = COLOR_BREAK;
        } else if (tc.isRunning() && _flowCalculator != null && _flowCalculator.isWarmedUp()) {
            // Color arc by flow quality during active work
            arcColor = getFlowColor(_flowCalculator.getFlowScore());
        } else if (tc.isRunning()) {
            arcColor = COLOR_WARMUP;
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

    //! Draw prominent flow score below the timer
    private function drawFlowScore(dc as Dc) as Void {
        if (_flowCalculator == null) { return; }

        var flowScore = _flowCalculator.getFlowScore();
        var flowColor = getFlowColor(flowScore);

        // Large flow score number
        dc.setColor(flowColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY + 25, Graphics.FONT_NUMBER_MILD,
                    flowScore.toString(), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Draw the flow zone label ("Flow" / "Focus" / "Distracted")
    private function drawFlowZoneLabel(dc as Dc) as Void {
        if (_flowCalculator == null) { return; }

        var zone = _flowCalculator.getFlowZone();
        var flowColor = getFlowColor(_flowCalculator.getFlowScore());

        dc.setColor(flowColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY + 55, Graphics.FONT_XTINY,
                    zone, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Draw trend arrow next to the flow score
    private function drawTrendArrow(dc as Dc) as Void {
        if (_flowCalculator == null) { return; }

        var trend = _flowCalculator.getTrend();
        if (trend == 0) { return; }  // Don't show arrow when stable

        var arrowX = _centerX + 45;
        var arrowY = _centerY + 25;

        if (trend > 0) {
            // Up arrow (green)
            dc.setColor(COLOR_FLOW_HIGH, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([
                [arrowX, arrowY - 8],
                [arrowX - 5, arrowY],
                [arrowX + 5, arrowY]
            ]);
        } else {
            // Down arrow (red)
            dc.setColor(COLOR_FLOW_LOW, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([
                [arrowX, arrowY + 8],
                [arrowX - 5, arrowY],
                [arrowX + 5, arrowY]
            ]);
        }
    }

    //! Draw warm-up indicator while sensors stabilize
    private function drawWarmupIndicator(dc as Dc) as Void {
        if (_flowCalculator == null) { return; }

        var progress = _flowCalculator.getWarmupProgress();

        dc.setColor(COLOR_WARMUP, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY + 30, Graphics.FONT_TINY,
                    "Calibrating...", Graphics.TEXT_JUSTIFY_CENTER);

        // Small progress bar
        var barWidth = 60;
        var barHeight = 4;
        var barX = _centerX - barWidth / 2;
        var barY = _centerY + 52;

        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(barX, barY, barWidth, barHeight);

        var fillWidth = (progress * barWidth) / 100;
        dc.setColor(COLOR_WARMUP, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(barX, barY, fillWidth, barHeight);
    }

    //! Draw session summary during break
    private function drawBreakSessionSummary(dc as Dc) as Void {
        if (_flowCalculator == null || _sessionManager == null) { return; }

        var avgFlow = _sessionManager.getSessionAvgFlowScore();
        var peakFlow = _flowCalculator.getPeakScore();
        var flowPct = _flowCalculator.getFlowZonePercent();

        // Only show if we have data from the completed work session
        if (avgFlow <= 0 && peakFlow <= 0) { return; }

        var y = _centerY + 30;

        // Avg flow
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX - 40, y, Graphics.FONT_XTINY, "Avg", Graphics.TEXT_JUSTIFY_RIGHT);
        dc.setColor(getFlowColor(avgFlow), Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX - 35, y, Graphics.FONT_XTINY, avgFlow.format("%d"), Graphics.TEXT_JUSTIFY_LEFT);

        // Peak flow
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX + 20, y, Graphics.FONT_XTINY, "Peak", Graphics.TEXT_JUSTIFY_RIGHT);
        dc.setColor(getFlowColor(peakFlow), Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX + 25, y, Graphics.FONT_XTINY, peakFlow.format("%d"), Graphics.TEXT_JUSTIFY_LEFT);

        // Flow zone percentage
        if (flowPct > 0) {
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, y + 18, Graphics.FONT_XTINY,
                        flowPct.format("%d") + "% in Flow", Graphics.TEXT_JUSTIFY_CENTER);
        }
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

        // Smaller timer when flow score is showing, to make room
        if (tc.isRunning() && tc.isWorkState() && _flowCalculator != null && _flowCalculator.isWarmedUp()) {
            dc.drawText(_centerX, _centerY - 25, Graphics.FONT_NUMBER_MILD,
                        timeString, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            dc.drawText(_centerX, _centerY - 15, Graphics.FONT_NUMBER_HOT,
                        timeString, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    //! Draw the state label (shown when not actively tracking flow)
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
        dc.drawText(_centerX, _centerY + 20, Graphics.FONT_SMALL,
                    stateLabel, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Draw sensor information (HR)
    private function drawSensorInfo(dc as Dc) as Void {
        if (_sensorManager == null) { return; }

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

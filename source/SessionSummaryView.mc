import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Post-session summary screen (both modes).
//! Shows duration, session label, flow score, and signal quality indicators.
class SessionSummaryView extends WatchUi.View {

    private var _durationSeconds as Number;
    private var _hrvScore        as Number;
    private var _movementScore   as Number;
    private var _mode            as Number;
    private var _label           as String;
    private var _converted       as Boolean;
    private var _hasBiometrics   as Boolean;

    private var _screenWidth  as Number = 0;
    private var _screenHeight as Number = 0;
    private var _centerX      as Number = 0;

    private const COLOR_BG       = 0x000000;
    private const COLOR_TEXT     = 0xFFFFFF;
    private const COLOR_TEXT_DIM = 0xAAAAAA;
    private const COLOR_ACCENT   = 0x44AAFF;
    private const COLOR_FLOW     = 0x44DDAA;
    private const COLOR_HIGH     = 0x44FF44;
    private const COLOR_MED      = 0xFFAA00;
    private const COLOR_LOW      = 0xFF4444;

    function initialize(duration as Number, hrvScore as Number,
                       movementScore as Number, mode as Number,
                       label as String, converted as Boolean,
                       hasBiometrics as Boolean) {
        View.initialize();
        _durationSeconds = duration;
        _hrvScore        = hrvScore;
        _movementScore   = movementScore;
        _mode            = mode;
        _label           = label;
        _converted       = converted;
        _hasBiometrics   = hasBiometrics;
    }

    function onLayout(dc as Dc) as Void {
        _screenWidth  = dc.getWidth();
        _screenHeight = dc.getHeight();
        _centerX = _screenWidth  / 2;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        // Title
        var title = _mode == MODE_FLOWTIMER ? "Session Done" : "Pomodoro Done";
        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 22, Graphics.FONT_SMALL,
                    title, Graphics.TEXT_JUSTIFY_CENTER);

        // Duration hero number
        var minutes = _durationSeconds / 60;
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 58, Graphics.FONT_NUMBER_MILD,
                    minutes.format("%d"), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 85, Graphics.FONT_XTINY,
                    "min focus", Graphics.TEXT_JUSTIFY_CENTER);

        // Session label (e.g., "Deep flow", "Pomodoro")
        var labelColor = _mode == MODE_FLOWTIMER ? COLOR_FLOW : COLOR_ACCENT;
        dc.setColor(labelColor, Graphics.COLOR_TRANSPARENT);
        var labelText = _label;
        if (_converted) {
            labelText = labelText + " (converted)";
        }
        dc.drawText(_centerX, 102, Graphics.FONT_XTINY,
                    labelText, Graphics.TEXT_JUSTIFY_CENTER);

        // Divider
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(50, 120, _screenWidth - 50, 120);

        if (_hasBiometrics) {
            // Signal rows
            var y = 132;
            drawSignalRow(dc, y, "HRV Quality", _hrvScore);
            y += 26;
            drawSignalRow(dc, y, "Stillness", _movementScore);

            // Flow score
            var flowScore = ((_hrvScore * 75) + (_movementScore * 25)) / 100;
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, y + 30, Graphics.FONT_XTINY,
                        "Flow Score: " + flowScore.format("%d"),
                        Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, 145, Graphics.FONT_SMALL,
                        "Flow: N/A", Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Dismiss hint
        dc.setColor(0x666666, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _screenHeight - 28, Graphics.FONT_XTINY,
                    "Press any key", Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawSignalRow(dc as Dc, y as Number, label as String,
                                   score as Number) as Void {
        var qualLabel = score >= 67 ? "High" : (score >= 34 ? "Med" : "Low");
        var qualColor = score >= 67 ? COLOR_HIGH : (score >= 34 ? COLOR_MED : COLOR_LOW);

        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(35, y, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(qualColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_screenWidth - 35, y, Graphics.FONT_XTINY,
                    qualLabel, Graphics.TEXT_JUSTIFY_RIGHT);
    }
}

//! Any-button dismiss delegate for SessionSummaryView
class SessionSummaryDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onNextPage() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onPreviousPage() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Shown after completing a full Pomodoro cycle (4 sessions)
class CycleSummaryView extends WatchUi.View {

    private var _cycleFocusTime as Number;
    private var _cycleDeepTime as Number;
    private var _quality as Number;          // -1 = no depth data
    private var _completedCycles as Number;

    private var _centerX as Number = 0;
    private var _centerY as Number = 0;

    function initialize(cycleFocusTime as Number, cycleDeepTime as Number,
                       quality as Number, completedCycles as Number) {
        View.initialize();
        _cycleFocusTime = cycleFocusTime;
        _cycleDeepTime = cycleDeepTime;
        _quality = quality;
        _completedCycles = completedCycles;
    }

    function onLayout(dc as Dc) as Void {
        _centerX = dc.getWidth() / 2;
        _centerY = dc.getHeight() / 2;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(0x000000, 0x000000);
        dc.clear();

        // Title
        dc.setColor(0x44DDAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 30, Graphics.FONT_SMALL,
                    "Cycle Complete", Graphics.TEXT_JUSTIFY_CENTER);

        // Deep minutes across the cycle (hero)
        var deepMinutes = _cycleDeepTime / 60;
        dc.setColor(0x44DDAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY - 30, Graphics.FONT_NUMBER_MILD,
                    deepMinutes.format("%d"), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY + 5, Graphics.FONT_XTINY,
                    "deep min of " + (_cycleFocusTime / 60).format("%d") + " focused",
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Divider
        dc.setColor(0x444444, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(_centerX - 60, _centerY + 30, _centerX + 60, _centerY + 30);

        // Cycle quality
        var qualityText;
        if (_quality >= 0) {
            qualityText = "Quality " + _quality.format("%d");
        } else {
            qualityText = "Quality: N/A";
        }
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY + 40, Graphics.FONT_TINY,
                    qualityText, Graphics.TEXT_JUSTIFY_CENTER);

        // Cycles today
        dc.drawText(_centerX, _centerY + 65, Graphics.FONT_XTINY,
                    _completedCycles.format("%d") + " cycles today",
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Dismiss hint
        dc.setColor(0x666666, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, dc.getHeight() - 35, Graphics.FONT_XTINY,
                    "Press any key", Graphics.TEXT_JUSTIFY_CENTER);
    }
}

//! Any-key dismiss delegate for CycleSummaryView
class CycleSummaryDelegate extends WatchUi.BehaviorDelegate {

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

    function onPreviousPage() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onNextPage() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Shown after completing a full Pomodoro cycle (4 sessions)
class CycleSummaryView extends WatchUi.View {

    private var _cycleFocusTime as Number;
    private var _avgFlowScore as Number;
    private var _hasBiometrics as Boolean;
    private var _completedCycles as Number;

    private var _centerX as Number = 0;
    private var _centerY as Number = 0;

    function initialize(cycleFocusTime as Number, avgFlowScore as Number,
                       hasBiometrics as Boolean, completedCycles as Number) {
        View.initialize();
        _cycleFocusTime = cycleFocusTime;
        _avgFlowScore = avgFlowScore;
        _hasBiometrics = hasBiometrics;
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

        // Total cycle focus time
        var minutes = _cycleFocusTime / 60;
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY - 30, Graphics.FONT_NUMBER_MILD,
                    minutes.format("%d"), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY + 5, Graphics.FONT_XTINY,
                    "min focus (4 sessions)", Graphics.TEXT_JUSTIFY_CENTER);

        // Divider
        dc.setColor(0x444444, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(_centerX - 60, _centerY + 30, _centerX + 60, _centerY + 30);

        // Flow score
        var flowText;
        if (_hasBiometrics) {
            flowText = "Avg Flow: " + _avgFlowScore.format("%d");
        } else {
            flowText = "Flow: N/A";
        }
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY + 40, Graphics.FONT_TINY,
                    flowText, Graphics.TEXT_JUSTIFY_CENTER);

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

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! View displayed after a work session completes, summarizing flow performance
class SessionSummaryView extends WatchUi.View {

    private var _avgFlowScore as Number;
    private var _peakFlowScore as Number;
    private var _flowZonePercent as Number;
    private var _durationSeconds as Number;
    private var _weakestComponent as String;

    // Screen dimensions
    private var _screenWidth as Number = 0;
    private var _screenHeight as Number = 0;
    private var _centerX as Number = 0;
    private var _centerY as Number = 0;

    // Colors
    private const COLOR_BG = 0x000000;
    private const COLOR_TEXT = 0xFFFFFF;
    private const COLOR_TEXT_DIM = 0xAAAAAA;
    private const COLOR_ACCENT = 0x44AAFF;
    private const COLOR_FLOW_LOW = 0xFF4444;
    private const COLOR_FLOW_MED = 0xFFAA00;
    private const COLOR_FLOW_HIGH = 0x44FF44;

    //! Constructor
    function initialize(avgFlow as Number, peakFlow as Number,
                       flowZonePct as Number, duration as Number,
                       weakest as String) {
        View.initialize();
        _avgFlowScore = avgFlow;
        _peakFlowScore = peakFlow;
        _flowZonePercent = flowZonePct;
        _durationSeconds = duration;
        _weakestComponent = weakest;
    }

    //! Load resources
    function onLayout(dc as Dc) as Void {
        _screenWidth = dc.getWidth();
        _screenHeight = dc.getHeight();
        _centerX = _screenWidth / 2;
        _centerY = _screenHeight / 2;
    }

    //! Update the view
    function onUpdate(dc as Dc) as Void {
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        // Title
        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 25, Graphics.FONT_SMALL,
                    "Session Done", Graphics.TEXT_JUSTIFY_CENTER);

        // Large average flow score as the hero
        var avgColor = getFlowColor(_avgFlowScore);
        dc.setColor(avgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 65, Graphics.FONT_NUMBER_MILD,
                    _avgFlowScore.toString(), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 90, Graphics.FONT_XTINY,
                    "Avg Flow", Graphics.TEXT_JUSTIFY_CENTER);

        // Divider
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(50, 108, _screenWidth - 50, 108);

        // Stats grid
        var y = 118;

        // Duration
        var minutes = _durationSeconds / 60;
        var seconds = _durationSeconds % 60;
        var durStr = minutes.format("%d") + ":" + seconds.format("%02d");
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(40, y, Graphics.FONT_XTINY, "Duration", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_screenWidth - 40, y, Graphics.FONT_XTINY, durStr, Graphics.TEXT_JUSTIFY_RIGHT);

        y += 20;

        // Peak flow
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(40, y, Graphics.FONT_XTINY, "Peak", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(getFlowColor(_peakFlowScore), Graphics.COLOR_TRANSPARENT);
        dc.drawText(_screenWidth - 40, y, Graphics.FONT_XTINY,
                    _peakFlowScore.format("%d"), Graphics.TEXT_JUSTIFY_RIGHT);

        y += 20;

        // Time in flow zone
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(40, y, Graphics.FONT_XTINY, "In Flow", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(COLOR_FLOW_HIGH, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_screenWidth - 40, y, Graphics.FONT_XTINY,
                    _flowZonePercent.format("%d") + "%", Graphics.TEXT_JUSTIFY_RIGHT);

        y += 20;

        // Weakest component hint (actionable insight)
        if (_avgFlowScore < 70 && !_weakestComponent.equals("")) {
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, y, Graphics.FONT_XTINY,
                        "Tip: " + _weakestComponent, Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Bottom hint
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _screenHeight - 30, Graphics.FONT_XTINY,
                    "Press any key", Graphics.TEXT_JUSTIFY_CENTER);
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
}

//! Delegate for session summary - any button dismisses
class SessionSummaryDelegate extends WatchUi.BehaviorDelegate {

    //! Constructor
    function initialize() {
        BehaviorDelegate.initialize();
    }

    //! Dismiss on select
    function onSelect() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    //! Dismiss on back
    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    //! Dismiss on any page
    function onNextPage() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    //! Dismiss on any page
    function onPreviousPage() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}

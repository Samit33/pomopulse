import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! View displayed after a work session completes.
//!
//! Shows duration as the headline, then three qualitative signal bars
//! (HRV Quality, Stillness, Recovery State) rated Low / Med / High.
//! No composite score — individual signals are honest and interpretable.
class SessionSummaryView extends WatchUi.View {

    private var _durationSeconds as Number;
    private var _hrvScore        as Number;  // 0-100
    private var _movementScore   as Number;  // 0-100 (higher = more still)
    private var _stressScore     as Number;  // 0-100 (higher = lower stress)

    // Screen dimensions
    private var _screenWidth  as Number = 0;
    private var _screenHeight as Number = 0;
    private var _centerX      as Number = 0;
    private var _centerY      as Number = 0;

    // Colors
    private const COLOR_BG       = 0x000000;
    private const COLOR_TEXT     = 0xFFFFFF;
    private const COLOR_TEXT_DIM = 0xAAAAAA;
    private const COLOR_ACCENT   = 0x44AAFF;
    private const COLOR_HIGH     = 0x44FF44;  // Green
    private const COLOR_MED      = 0xFFAA00;  // Amber
    private const COLOR_LOW      = 0xFF4444;  // Red

    //! Constructor
    //! @param duration     Session length in seconds
    //! @param hrvScore     HRV component score (0-100)
    //! @param movementScore  Stillness score (0-100, higher = more still)
    //! @param stressScore  Recovery/stress score (0-100, higher = less stressed)
    function initialize(duration as Number, hrvScore as Number,
                       movementScore as Number, stressScore as Number) {
        View.initialize();
        _durationSeconds = duration;
        _hrvScore        = hrvScore;
        _movementScore   = movementScore;
        _stressScore     = stressScore;
    }

    //! Load resources
    function onLayout(dc as Dc) as Void {
        _screenWidth  = dc.getWidth();
        _screenHeight = dc.getHeight();
        _centerX = _screenWidth  / 2;
        _centerY = _screenHeight / 2;
    }

    //! Update the view
    function onUpdate(dc as Dc) as Void {
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        // Title
        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 22, Graphics.FONT_SMALL,
                    "Session Done", Graphics.TEXT_JUSTIFY_CENTER);

        // Duration as the hero number
        var minutes = _durationSeconds / 60;
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 60, Graphics.FONT_NUMBER_MILD,
                    minutes.format("%d"), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 88, Graphics.FONT_XTINY,
                    "min focus", Graphics.TEXT_JUSTIFY_CENTER);

        // Divider
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(50, 106, _screenWidth - 50, 106);

        // Three signal rows
        var y = 118;
        drawSignalRow(dc, y, "HRV Quality",  _hrvScore);
        y += 26;
        drawSignalRow(dc, y, "Stillness",    _movementScore);
        y += 26;
        drawSignalRow(dc, y, "Recovery",     _stressScore);

        // Bottom hint
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _screenHeight - 28, Graphics.FONT_XTINY,
                    "Press any key", Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Draw one signal row: label on left, Low/Med/High on right
    private function drawSignalRow(dc as Dc, y as Number, label as String,
                                   score as Number) as Void {
        var qualLabel = getQualityLabel(score);
        var qualColor = getQualityColor(score);

        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(35, y, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(qualColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_screenWidth - 35, y, Graphics.FONT_XTINY,
                    qualLabel, Graphics.TEXT_JUSTIFY_RIGHT);
    }

    //! Return "High", "Med", or "Low" based on score
    private function getQualityLabel(score as Number) as String {
        if (score >= 67) { return "High"; }
        if (score >= 34) { return "Med"; }
        return "Low";
    }

    //! Return color matching quality label
    private function getQualityColor(score as Number) as Number {
        if (score >= 67) { return COLOR_HIGH; }
        if (score >= 34) { return COLOR_MED; }
        return COLOR_LOW;
    }
}

//! Delegate for session summary — any button dismisses
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

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Gather everything the summary screen needs from the calculator,
//! in one place, before the calculator is reset.
function collectSessionStats(fc as FlowScoreCalculator?, duration as Number,
                             mode as Number, label as String,
                             converted as Boolean) as Dictionary {
    var stats = {
        "duration"      => duration,
        "mode"          => mode,
        "label"         => label,
        "converted"     => converted,
        "avgFlow"       => 0,
        "peakFlow"      => 0,
        "timeToFlow"    => -1,
        "longestStreak" => 0,
        "zoneFlowPct"   => 0,
        "zoneFocusPct"  => 0,
        "hrvScore"      => 0,
        "movementScore" => 0,
        "hasBiometrics" => false,
        "calibrated"    => false,
        "trend"         => null
    } as Dictionary;

    if (fc != null) {
        stats["avgFlow"]       = fc.getAvgScore();
        stats["peakFlow"]      = fc.getPeakScore();
        stats["timeToFlow"]    = fc.getTimeToFlow();
        stats["longestStreak"] = fc.getLongestFlowStreak();
        stats["zoneFlowPct"]   = fc.getFlowZonePercent();
        stats["zoneFocusPct"]  = fc.getFocusZonePercent();
        stats["hrvScore"]      = fc.getHrvScore();
        stats["movementScore"] = fc.getMovementScore();
        stats["hasBiometrics"] = fc.hasBiometrics();
        stats["calibrated"]    = fc.isCalibrated();
        stats["trend"]         = fc.getTrend();
    }
    return stats;
}

//! Post-session summary (both modes).
//! Page 1: flow score hero, session sparkline, zone bar.
//! Page 2 (DOWN): signal detail — HRV quality, stillness, streaks.
class SessionSummaryView extends WatchUi.View {

    private var _stats as Dictionary;
    private var _page  as Number = 0;

    private var _screenWidth  as Number = 0;
    private var _screenHeight as Number = 0;
    private var _centerX      as Number = 0;

    private const COLOR_BG       = 0x000000;
    private const COLOR_TEXT     = 0xFFFFFF;
    private const COLOR_TEXT_DIM = 0xAAAAAA;
    private const COLOR_ACCENT   = 0x44AAFF;
    private const COLOR_FLOW     = 0x44DDAA;
    private const COLOR_FOCUS    = 0x4488FF;
    private const COLOR_BUILD    = 0x555555;
    private const COLOR_HIGH     = 0x44FF44;
    private const COLOR_MED      = 0xFFAA00;
    private const COLOR_LOW      = 0xFF4444;

    function initialize(stats as Dictionary) {
        View.initialize();
        _stats = stats;
    }

    function onLayout(dc as Dc) as Void {
        _screenWidth  = dc.getWidth();
        _screenHeight = dc.getHeight();
        _centerX = _screenWidth  / 2;
    }

    function togglePage() as Void {
        _page = _page == 0 ? 1 : 0;
        WatchUi.requestUpdate();
    }

    private function statNum(key as String) as Number {
        if (_stats.hasKey(key) && _stats[key] instanceof Number) {
            return _stats[key] as Number;
        }
        return 0;
    }

    private function statBool(key as String) as Boolean {
        if (_stats.hasKey(key) && _stats[key] instanceof Boolean) {
            return _stats[key] as Boolean;
        }
        return false;
    }

    private function scoreColor(score as Number) as Number {
        if (score >= 70) { return COLOR_FLOW; }
        if (score >= 40) { return COLOR_FOCUS; }
        return COLOR_TEXT_DIM;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        if (_page == 0) {
            drawMainPage(dc);
        } else {
            drawDetailPage(dc);
        }
    }

    // ── Page 1: flow overview ─────────────────────────────────

    private function drawMainPage(dc as Dc) as Void {
        var mode          = statNum("mode");
        var hasBiometrics = statBool("hasBiometrics");
        var duration      = statNum("duration");
        var minutes       = duration / 60;

        // Title
        var title = mode == MODE_FLOWTIMER ? "Session Done" : "Pomodoro Done";
        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 20, Graphics.FONT_SMALL,
                    title, Graphics.TEXT_JUSTIFY_CENTER);

        if (!hasBiometrics) {
            // No HRV: duration becomes the hero
            dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, 88, Graphics.FONT_NUMBER_MILD,
                        minutes.format("%d"),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, 118, Graphics.FONT_XTINY,
                        "min focus", Graphics.TEXT_JUSTIFY_CENTER);
            drawLabelLine(dc, 142);
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, 168, Graphics.FONT_XTINY,
                        "No HRV data - check watch fit",
                        Graphics.TEXT_JUSTIFY_CENTER);
            drawDismissHint(dc);
            return;
        }

        // Hero: average flow score
        var avgFlow = statNum("avgFlow");
        dc.setColor(scoreColor(avgFlow), Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 68, Graphics.FONT_NUMBER_MILD,
                    avgFlow.format("%d"),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 96, Graphics.FONT_XTINY,
                    "avg flow", Graphics.TEXT_JUSTIFY_CENTER);

        // Duration + peak, one line
        var peakFlow = statNum("peakFlow");
        dc.drawText(_centerX, 114, Graphics.FONT_XTINY,
                    minutes.format("%d") + " min  -  peak " + peakFlow.format("%d"),
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Session sparkline
        drawSparkline(dc, 136, 34);

        // Zone bar (flow / focus / other)
        drawZoneBar(dc, 180);

        // Time-to-flow footnote
        var timeToFlow = statNum("timeToFlow");
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        if (timeToFlow >= 0) {
            dc.drawText(_centerX, 194, Graphics.FONT_XTINY,
                        "First flow in " + (timeToFlow / 60).format("%d") + " min",
                        Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.drawText(_centerX, 194, Graphics.FONT_XTINY,
                        "Flow zone not reached",
                        Graphics.TEXT_JUSTIFY_CENTER);
        }

        drawDismissHint(dc);
    }

    private function drawLabelLine(dc as Dc, y as Number) as Void {
        var mode = statNum("mode");
        var labelColor = mode == MODE_FLOWTIMER ? COLOR_FLOW : COLOR_ACCENT;
        var labelText = _stats.hasKey("label") ? (_stats["label"] as String) : "";
        if (statBool("converted")) {
            labelText = labelText + " (converted)";
        }
        dc.setColor(labelColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, y, Graphics.FONT_XTINY,
                    labelText, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Minute-by-minute flow score line chart
    private function drawSparkline(dc as Dc, top as Number, height as Number) as Void {
        var trend = null;
        if (_stats.hasKey("trend") && _stats["trend"] instanceof Array) {
            trend = _stats["trend"] as Array<Number>;
        }

        var chartW = 150;
        var left = _centerX - (chartW / 2);
        var bottom = top + height;

        if (trend == null || trend.size() < 2) {
            dc.setColor(COLOR_BUILD, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, top + (height / 2) - 8, Graphics.FONT_XTINY,
                        "(session too short for trend)",
                        Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        // Flow threshold guide line (score 70)
        var thresholdY = bottom - ((70 * height) / 100);
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(left, thresholdY, left + chartW, thresholdY);

        // Score polyline
        dc.setColor(COLOR_FLOW, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        var count = trend.size();
        var prevX = left;
        var prevY = bottom - ((trend[0] * height) / 100);
        for (var i = 1; i < count; i++) {
            var x = left + ((i * chartW) / (count - 1));
            var y = bottom - ((trend[i] * height) / 100);
            dc.drawLine(prevX, prevY, x, y);
            prevX = x;
            prevY = y;
        }
        dc.setPenWidth(1);
    }

    //! Stacked horizontal bar: time in flow / focused / building
    private function drawZoneBar(dc as Dc, y as Number) as Void {
        var barW = 150;
        var barH = 8;
        var left = _centerX - (barW / 2);

        var flowPct  = statNum("zoneFlowPct");
        var focusPct = statNum("zoneFocusPct");

        var flowW  = (barW * flowPct) / 100;
        var focusW = (barW * focusPct) / 100;

        // Base (building/distracted remainder)
        dc.setColor(COLOR_BUILD, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(left, y, barW, barH);

        // Flow segment then focus segment
        if (flowW > 0) {
            dc.setColor(COLOR_FLOW, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(left, y, flowW, barH);
        }
        if (focusW > 0) {
            dc.setColor(COLOR_FOCUS, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(left + flowW, y, focusW, barH);
        }
    }

    // ── Page 2: signal detail ─────────────────────────────────

    private function drawDetailPage(dc as Dc) as Void {
        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 20, Graphics.FONT_SMALL,
                    "Signals", Graphics.TEXT_JUSTIFY_CENTER);

        var y = 60;
        drawSignalRow(dc, y, "HRV Quality", statNum("hrvScore"));
        y += 28;
        drawSignalRow(dc, y, "Stillness", statNum("movementScore"));
        y += 28;

        // Longest unbroken flow streak
        var streak = statNum("longestStreak");
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(50, y, Graphics.FONT_XTINY, "Best streak", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_screenWidth - 50, y, Graphics.FONT_XTINY,
                    (streak / 60).format("%d") + " min", Graphics.TEXT_JUSTIFY_RIGHT);
        y += 28;

        // Zone percentages
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(50, y, Graphics.FONT_XTINY, "Time in flow", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(COLOR_FLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_screenWidth - 50, y, Graphics.FONT_XTINY,
                    statNum("zoneFlowPct").format("%d") + "%", Graphics.TEXT_JUSTIFY_RIGHT);
        y += 28;

        // Baseline calibration status
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        if (statBool("calibrated")) {
            dc.drawText(_centerX, y + 6, Graphics.FONT_XTINY,
                        "Scored vs your HRV baseline",
                        Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.drawText(_centerX, y + 6, Graphics.FONT_XTINY,
                        "Calibrating your baseline...",
                        Graphics.TEXT_JUSTIFY_CENTER);
        }

        dc.setColor(0x666666, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _screenHeight - 28, Graphics.FONT_XTINY,
                    "UP: back  -  START: done", Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawSignalRow(dc as Dc, y as Number, label as String,
                                   score as Number) as Void {
        var qualLabel = score >= 67 ? "High" : (score >= 34 ? "Med" : "Low");
        var qualColor = score >= 67 ? COLOR_HIGH : (score >= 34 ? COLOR_MED : COLOR_LOW);

        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(50, y, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(qualColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_screenWidth - 50, y, Graphics.FONT_XTINY,
                    qualLabel, Graphics.TEXT_JUSTIFY_RIGHT);
    }

    private function drawDismissHint(dc as Dc) as Void {
        dc.setColor(0x666666, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _screenHeight - 28, Graphics.FONT_XTINY,
                    "DOWN: details  -  START: done", Graphics.TEXT_JUSTIFY_CENTER);
    }
}

//! Summary delegate: START/BACK dismiss, UP/DOWN toggle detail page
class SessionSummaryDelegate extends WatchUi.BehaviorDelegate {

    private var _view as SessionSummaryView?;

    function initialize(view as SessionSummaryView?) {
        BehaviorDelegate.initialize();
        _view = view;
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
        if (_view != null) {
            _view.togglePage();
        }
        return true;
    }

    function onPreviousPage() as Boolean {
        if (_view != null) {
            _view.togglePage();
        }
        return true;
    }
}

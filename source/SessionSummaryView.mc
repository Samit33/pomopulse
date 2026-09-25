import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Gather everything the summary screen needs from the engine,
//! in one place, before the engine is reset.
function collectSessionStats(engine as DeepWorkEngine?, duration as Number,
                             mode as Number, label as String,
                             converted as Boolean) as Dictionary {
    var stats = {
        "duration"      => duration,
        "mode"          => mode,
        "label"         => label,
        "converted"     => converted,
        "quality"       => 0,
        "deepSec"       => 0,
        "deepPct"       => 0,
        "focusPct"      => 0,
        "interruptions" => 0,
        "manual"        => 0,
        "longest"       => 0,
        "timeToDeep"    => -1,
        "engagement"    => 0,
        "hasData"       => false,
        "hasPhysiology" => false,
        "calibrated"    => false,
        "rating"        => 0,
        "trend"         => null
    } as Dictionary;

    if (engine != null) {
        stats["quality"]       = engine.getQuality();
        stats["deepSec"]       = engine.getDeepSeconds();
        stats["deepPct"]       = engine.getDeepPercent();
        stats["focusPct"]      = engine.getFocusPercent();
        stats["interruptions"] = engine.getInterruptions();
        stats["manual"]        = engine.getManualDistractions();
        stats["longest"]       = engine.getLongestBlock();
        stats["timeToDeep"]    = engine.getTimeToDeep();
        stats["engagement"]    = engine.getAvgEngagement();
        stats["hasData"]       = engine.hasData();
        stats["hasPhysiology"] = engine.hasPhysiology();
        stats["calibrated"]    = engine.isCalibrated();
        stats["trend"]         = engine.getTrend();
    }
    return stats;
}

//! Name of a self-rating / verdict step (1 shallow .. 3 deep)
function ratingName(rating as Number) as String {
    if (rating >= 3) { return "Deep"; }
    if (rating == 2) { return "Solid"; }
    return "Shallow";
}

//! Post-session summary (both modes).
//! Page 1: quality hero, deep minutes, depth sparkline, zone bar,
//!         interruptions, and your rating vs. the watch's verdict.
//! Page 2 (DOWN): breakdown + one concrete coaching tip.
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
    private const COLOR_DEEP     = 0x44DDAA;
    private const COLOR_FOCUS    = 0x4488FF;
    private const COLOR_SHALLOW  = 0x555555;
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
        if (score >= 70) { return COLOR_DEEP; }
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

    // ── Page 1: overview ──────────────────────────────────────

    private function drawMainPage(dc as Dc) as Void {
        var mode     = statNum("mode");
        var duration = statNum("duration");
        var minutes  = duration / 60;

        var title = mode == MODE_FLOWTIMER ? "Session Done" : "Pomodoro Done";
        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 20, Graphics.FONT_SMALL,
                    title, Graphics.TEXT_JUSTIFY_CENTER);

        if (!statBool("hasData")) {
            // No sensor data at all: duration becomes the hero
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
                        "No sensor data recorded",
                        Graphics.TEXT_JUSTIFY_CENTER);
            drawDismissHint(dc, "DOWN: details  -  START: done");
            return;
        }

        // Hero: deep work quality
        var quality = statNum("quality");
        dc.setColor(scoreColor(quality), Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 66, Graphics.FONT_NUMBER_MILD,
                    quality.format("%d"),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 92, Graphics.FONT_XTINY,
                    "deep work quality", Graphics.TEXT_JUSTIFY_CENTER);

        // Deep minutes out of total
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 110, Graphics.FONT_XTINY,
                    (statNum("deepSec") / 60).format("%d") + " deep min of " + minutes.format("%d"),
                    Graphics.TEXT_JUSTIFY_CENTER);

        drawSparkline(dc, 134, 32);
        drawZoneBar(dc, 172);

        // Interruptions + best unbroken block
        var intr = statNum("interruptions");
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 184, Graphics.FONT_XTINY,
                    intr.format("%d") + (intr == 1 ? " break-in" : " break-ins") +
                    "  -  best " + (statNum("longest") / 60).format("%d") + "m",
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Your rating vs. the watch's verdict
        var rating = statNum("rating");
        if (rating > 0) {
            var verdict = quality >= 70 ? 3 : (quality >= 40 ? 2 : 1);
            dc.setColor(rating == verdict ? COLOR_DEEP : COLOR_MED, Graphics.COLOR_TRANSPARENT);
            var verdictText;
            if (rating == verdict) {
                verdictText = "Watch agrees: " + ratingName(verdict);
            } else {
                verdictText = "You " + ratingName(rating) + ", watch " + ratingName(verdict);
            }
            dc.drawText(_centerX, 204, Graphics.FONT_XTINY,
                        verdictText, Graphics.TEXT_JUSTIFY_CENTER);
        }

        drawDismissHint(dc, "DOWN: details  -  START: done");
    }

    private function drawLabelLine(dc as Dc, y as Number) as Void {
        var mode = statNum("mode");
        var labelColor = mode == MODE_FLOWTIMER ? COLOR_DEEP : COLOR_ACCENT;
        var labelText = _stats.hasKey("label") ? (_stats["label"] as String) : "";
        if (statBool("converted")) {
            labelText = labelText + " (converted)";
        }
        dc.setColor(labelColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, y, Graphics.FONT_XTINY,
                    labelText, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Minute-by-minute depth line chart — shows the build-up and every
    //! knock-down across the session
    private function drawSparkline(dc as Dc, top as Number, height as Number) as Void {
        var trend = null;
        if (_stats.hasKey("trend") && _stats["trend"] instanceof Array) {
            trend = _stats["trend"] as Array<Number>;
        }

        var chartW = 150;
        var left = _centerX - (chartW / 2);
        var bottom = top + height;

        if (trend == null || trend.size() < 2) {
            dc.setColor(COLOR_SHALLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, top + (height / 2) - 8, Graphics.FONT_XTINY,
                        "(session too short for trend)",
                        Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        // Deep threshold guide line (depth 70)
        var thresholdY = bottom - ((70 * height) / 100);
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(left, thresholdY, left + chartW, thresholdY);

        dc.setColor(COLOR_DEEP, Graphics.COLOR_TRANSPARENT);
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

    //! Stacked horizontal bar: time deep / focused / shallow
    private function drawZoneBar(dc as Dc, y as Number) as Void {
        var barW = 150;
        var barH = 8;
        var left = _centerX - (barW / 2);

        var deepW  = (barW * statNum("deepPct")) / 100;
        var focusW = (barW * statNum("focusPct")) / 100;

        dc.setColor(COLOR_SHALLOW, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(left, y, barW, barH);
        if (deepW > 0) {
            dc.setColor(COLOR_DEEP, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(left, y, deepW, barH);
        }
        if (focusW > 0) {
            dc.setColor(COLOR_FOCUS, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(left + deepW, y, focusW, barH);
        }
    }

    // ── Page 2: breakdown + coaching ─────────────────────────

    private function drawDetailPage(dc as Dc) as Void {
        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 20, Graphics.FONT_SMALL,
                    "Breakdown", Graphics.TEXT_JUSTIFY_CENTER);

        var y = 54;
        drawRow(dc, y, "Deep time", statNum("deepPct").format("%d") + "%", COLOR_DEEP);
        y += 24;

        var intr = statNum("interruptions");
        var manual = statNum("manual");
        var intrText = intr.format("%d");
        if (manual > 0) {
            intrText = intrText + " (" + manual.format("%d") + " tapped)";
        }
        drawRow(dc, y, "Break-ins", intrText, intr == 0 ? COLOR_HIGH : COLOR_TEXT);
        y += 24;

        drawRow(dc, y, "Longest block",
                (statNum("longest") / 60).format("%d") + " min", COLOR_TEXT);
        y += 24;

        var ttd = statNum("timeToDeep");
        drawRow(dc, y, "Time to deep",
                ttd >= 0 ? (ttd / 60).format("%d") + " min" : "never", COLOR_TEXT);
        y += 24;

        if (statBool("hasPhysiology")) {
            var eng = statNum("engagement");
            var engLabel = eng >= 80 ? "High" : (eng >= 60 ? "Med" : "Low");
            var engColor = eng >= 80 ? COLOR_HIGH : (eng >= 60 ? COLOR_MED : COLOR_LOW);
            if (!statBool("calibrated")) {
                engLabel = "Calibrating";
                engColor = COLOR_TEXT_DIM;
            }
            drawRow(dc, y, "Engagement", engLabel, engColor);
        } else {
            drawRow(dc, y, "Engagement", "No HR", COLOR_TEXT_DIM);
        }

        // One concrete, actionable takeaway
        var tip = coachingTip();
        dc.setColor(COLOR_MED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 180, Graphics.FONT_XTINY, tip[0], Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 200, Graphics.FONT_XTINY, tip[1], Graphics.TEXT_JUSTIFY_CENTER);

        drawDismissHint(dc, "UP: back  -  START: done");
    }

    //! Pick the single most useful takeaway for this session
    private function coachingTip() as Array<String> {
        var minutes  = statNum("duration") / 60;
        var intr     = statNum("interruptions");
        var manual   = statNum("manual");
        var longest  = statNum("longest") / 60;
        var ttd      = statNum("timeToDeep");
        var quality  = statNum("quality");
        var perHourTenths = minutes > 0 ? (intr * 600) / minutes : 0;

        if (perHourTenths >= 40) {
            return ["Broken up " + intr.format("%d") + " times.",
                    "Put phone out of reach"] as Array<String>;
        }
        if (manual >= 3) {
            return ["Mind kept wandering.",
                    "Note it down, refocus"] as Array<String>;
        }
        if (ttd < 0 && minutes >= 20) {
            return ["Never settled in.",
                    "Pick one clear goal"] as Array<String>;
        }
        if (longest >= 45) {
            return ["Superb: " + longest.format("%d") + "m unbroken.",
                    "Protect this time slot"] as Array<String>;
        }
        if (statBool("hasPhysiology") && statBool("calibrated") &&
            statNum("engagement") < 60) {
            return ["Low engagement signals.",
                    "Move or hydrate first"] as Array<String>;
        }
        if (ttd > 720) {
            return ["Slow start: " + (ttd / 60).format("%d") + "m to deep",
                    "Try a startup ritual"] as Array<String>;
        }
        if (minutes < 25 && quality >= 60) {
            return ["Go longer next time:",
                    "depth builds with time"] as Array<String>;
        }
        return ["Solid session.",
                "Same time tomorrow?"] as Array<String>;
    }

    private function drawRow(dc as Dc, y as Number, label as String,
                             value as String, valueColor as Number) as Void {
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(40, y, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_screenWidth - 40, y, Graphics.FONT_XTINY,
                    value, Graphics.TEXT_JUSTIFY_RIGHT);
    }

    private function drawDismissHint(dc as Dc, text as String) as Void {
        dc.setColor(0x666666, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _screenHeight - 28, Graphics.FONT_XTINY,
                    text, Graphics.TEXT_JUSTIFY_CENTER);
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
        var view = _view;
        if (view != null) {
            view.togglePage();
        }
        return true;
    }

    function onPreviousPage() as Boolean {
        var view = _view;
        if (view != null) {
            view.togglePage();
        }
        return true;
    }
}

//! "How deep was it?" — asked right after a session, before the watch's
//! score is shown. Self-report is the ground truth of deep work; over time
//! it tells you how far to trust the watch (Stats > Insights).
class SelfRatingMenu extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({:title => "How deep was it?"});
        addItem(new WatchUi.MenuItem("Deep", "Lost track of time", 3, null));
        addItem(new WatchUi.MenuItem("Solid", "Some drift", 2, null));
        addItem(new WatchUi.MenuItem("Shallow", "Scattered", 1, null));
    }
}

//! Stores the rating with the saved session; BACK skips rating
class SelfRatingDelegate extends WatchUi.Menu2InputDelegate {

    private var _stats as Dictionary;
    private var _timestamp as Number;

    function initialize(stats as Dictionary, timestamp as Number) {
        Menu2InputDelegate.initialize();
        _stats = stats;
        _timestamp = timestamp;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var rating = item.getId() as Number;
        _stats["rating"] = rating;
        var hm = getApp().getHistoryManager();
        if (hm != null) {
            hm.setSelfRating(_timestamp, rating);
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

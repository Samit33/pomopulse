import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

//! Stats: four pages navigated with UP/DOWN.
//! Page 0: Today — deep minutes vs goal, quality, session list
//! Page 1: Week — 7-day deep-vs-focus bar chart
//! Page 2: Insights — peak hours, sweet-spot length, break-in rate,
//!         how well the watch agrees with your own ratings
//! Page 3: Records — streak and personal bests
class StatsView extends WatchUi.View {

    private var _historyManager as HistoryManager?;
    private var _page as Number = 0;

    private const PAGE_COUNT = 4;

    private var _screenWidth  as Number = 0;
    private var _screenHeight as Number = 0;
    private var _centerX      as Number = 0;

    private const COLOR_BG        = 0x000000;
    private const COLOR_TEXT      = 0xFFFFFF;
    private const COLOR_TEXT_DIM  = 0xAAAAAA;
    private const COLOR_ACCENT    = 0x44AAFF;
    private const COLOR_FLOW      = 0x44DDAA;
    private const COLOR_POMO      = 0x4488FF;
    private const COLOR_TIME      = 0x44FF44;
    private const COLOR_INACTIVE  = 0x444444;
    private const COLOR_BAR_DIM   = 0x2A5577;

    private const SESSION_ROW_H = 26;
    private const MAX_VISIBLE   = 3;

    function initialize(historyManager as HistoryManager?) {
        View.initialize();
        _historyManager = historyManager;
    }

    function onLayout(dc as Dc) as Void {
        _screenWidth  = dc.getWidth();
        _screenHeight = dc.getHeight();
        _centerX = _screenWidth  / 2;
    }

    function nextPage() as Void {
        if (_page < PAGE_COUNT - 1) {
            _page++;
            WatchUi.requestUpdate();
        }
    }

    function prevPage() as Void {
        if (_page > 0) {
            _page--;
            WatchUi.requestUpdate();
        }
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        if (_historyManager == null) {
            drawCenteredNote(dc, "No data");
            return;
        }

        if (_page == 0) {
            drawTodayPage(dc);
        } else if (_page == 1) {
            drawWeekPage(dc);
        } else if (_page == 2) {
            drawInsightsPage(dc);
        } else {
            drawRecordsPage(dc);
        }

        drawPageDots(dc);
    }

    private function drawCenteredNote(dc as Dc, text as String) as Void {
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _screenHeight / 2, Graphics.FONT_MEDIUM,
                    text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawPageDots(dc as Dc) as Void {
        var y = _screenHeight - 14;
        var spacing = 12;
        var startX = _centerX - (((PAGE_COUNT - 1) * spacing) / 2);
        for (var i = 0; i < PAGE_COUNT; i++) {
            dc.setColor(i == _page ? COLOR_TEXT_DIM : COLOR_INACTIVE,
                        Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(startX + (i * spacing), y, i == _page ? 3 : 2);
        }
    }

    // ── Page 0: Today ─────────────────────────────────────────

    private function drawTodayPage(dc as Dc) as Void {
        var hm = _historyManager;
        if (hm == null) { return; }

        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 20, Graphics.FONT_SMALL,
                    "Today", Graphics.TEXT_JUSTIFY_CENTER);

        var goal = getDeepGoalMinutes();
        var todaySessions = hm.getTodaySessions();
        if (todaySessions.size() == 0) {
            drawCenteredNote(dc, "No sessions yet");
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, (_screenHeight / 2) + 24, Graphics.FONT_XTINY,
                        "Goal: " + goal.format("%d") + " deep min",
                        Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        // Hero: deep minutes today vs goal
        var deepMin = hm.getTodayDeepTime() / 60;
        dc.setColor(deepMin >= goal ? COLOR_FLOW : COLOR_TIME, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 44, Graphics.FONT_MEDIUM,
                    deepMin.format("%d") + "/" + goal.format("%d") + "m",
                    Graphics.TEXT_JUSTIFY_CENTER);

        var y = 76;
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, y, Graphics.FONT_XTINY,
                    "deep of " + hm.formatDurationCompact(hm.getTodayFocusTime()) + " focus",
                    Graphics.TEXT_JUSTIFY_CENTER);
        y += 18;

        var quality = hm.getTodayAvgQuality();
        if (quality >= 0) {
            var intr = hm.getTodayInterruptions();
            dc.setColor(qualityColor(quality), Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, y, Graphics.FONT_XTINY,
                        "Quality " + quality.format("%d") + "  -  " + intr.format("%d") + " break-ins",
                        Graphics.TEXT_JUSTIFY_CENTER);
            y += 18;
        }

        // Divider
        var divY = y + 3;
        dc.setColor(COLOR_INACTIVE, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(45, divY, _screenWidth - 45, divY);

        // Session list (most recent first)
        var listY = divY + 8;
        var visible = todaySessions.size() < MAX_VISIBLE ? todaySessions.size() : MAX_VISIBLE;
        for (var i = 0; i < visible; i++) {
            drawSessionRow(dc, todaySessions[i] as Dictionary, listY);
            listY += SESSION_ROW_H;
        }

        if (todaySessions.size() > MAX_VISIBLE) {
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, listY, Graphics.FONT_XTINY,
                        "+" + (todaySessions.size() - MAX_VISIBLE).format("%d") + " more",
                        Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    private function qualityColor(quality as Number) as Number {
        if (quality >= 70) { return COLOR_FLOW; }
        if (quality >= 40) { return COLOR_POMO; }
        return COLOR_TEXT_DIM;
    }

    //! Row: mode, start time, quality, deep/total minutes
    private function drawSessionRow(dc as Dc, session as Dictionary, y as Number) as Void {
        var hm = _historyManager;
        if (hm == null) { return; }

        var timestamp = hm.sessionNum(session, "timestamp", 0);
        var duration  = hm.sessionNum(session, "duration", 0);

        var mode = hm.getSessionMode(session);
        var modeChar = mode == MODE_FLOWTIMER ? "F" : "P";
        var modeColor = mode == MODE_FLOWTIMER ? COLOR_FLOW : COLOR_POMO;

        var converted = session.hasKey("converted") && (session["converted"] as Boolean);

        var info = Gregorian.info(new Time.Moment(timestamp), Time.FORMAT_SHORT);
        var timeStr = info.hour.format("%02d") + ":" + info.min.format("%02d");
        if (converted) {
            timeStr = timeStr + "*";
        }

        dc.setColor(modeColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(32, y, Graphics.FONT_XTINY, modeChar, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(46, y, Graphics.FONT_XTINY, timeStr, Graphics.TEXT_JUSTIFY_LEFT);

        if (hm.hasQuality(session)) {
            var quality = hm.sessionNum(session, "quality", 0);
            dc.setColor(qualityColor(quality), Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX + 22, y, Graphics.FONT_XTINY,
                        quality.format("%d"), Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_screenWidth - 32, y, Graphics.FONT_XTINY,
                        (hm.sessionNum(session, "deepSec", 0) / 60).format("%d") + "/" +
                        (duration / 60).format("%d") + "m",
                        Graphics.TEXT_JUSTIFY_RIGHT);
        } else {
            // Legacy session (before depth tracking): duration only
            dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_screenWidth - 32, y, Graphics.FONT_XTINY,
                        hm.formatDurationCompact(duration), Graphics.TEXT_JUSTIFY_RIGHT);
        }
    }

    // ── Page 1: Week ──────────────────────────────────────────

    private function drawWeekPage(dc as Dc) as Void {
        var hm = _historyManager;
        if (hm == null) { return; }

        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 20, Graphics.FONT_SMALL,
                    "Last 7 Days", Graphics.TEXT_JUSTIFY_CENTER);

        var focusDays = hm.getLast7DayFocus();
        var deepDays = hm.getLast7DayDeep();

        var weekFocus = 0;
        var weekDeep = 0;
        var maxDay = 0;
        for (var i = 0; i < 7; i++) {
            weekFocus += focusDays[i];
            weekDeep += deepDays[i];
            if (focusDays[i] > maxDay) {
                maxDay = focusDays[i];
            }
        }

        if (weekFocus == 0) {
            drawCenteredNote(dc, "No sessions yet");
            return;
        }

        dc.setColor(COLOR_FLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 44, Graphics.FONT_MEDIUM,
                    hm.formatDurationCompact(weekDeep), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 76, Graphics.FONT_XTINY,
                    "deep of " + hm.formatDurationCompact(weekFocus) + " focus",
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Stacked bars: full height = focus time, bright part = deep time
        var barW = 16;
        var gap = 8;
        var chartW = (7 * barW) + (6 * gap);
        var left = _centerX - (chartW / 2);
        var chartBottom = 182;
        var maxBarH = 76;

        for (var i = 0; i < 7; i++) {
            var x = left + (i * (barW + gap));
            var barH = maxDay > 0 ? (focusDays[i] * maxBarH) / maxDay : 0;
            if (focusDays[i] > 0 && barH < 3) {
                barH = 3;
            }
            if (barH > 0) {
                dc.setColor(COLOR_BAR_DIM, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x, chartBottom - barH, barW, barH);
                var deepH = maxDay > 0 ? (deepDays[i] * maxBarH) / maxDay : 0;
                if (deepH > 0) {
                    dc.setColor(COLOR_FLOW, Graphics.COLOR_TRANSPARENT);
                    dc.fillRectangle(x, chartBottom - deepH, barW, deepH);
                }
            } else {
                dc.setColor(COLOR_INACTIVE, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x, chartBottom - 2, barW, 2);
            }
        }

        // Day-of-week letters under the bars; today in white
        var letters = ["S", "M", "T", "W", "T", "F", "S"] as Array<String>;
        var todayInfo = Gregorian.info(Time.today(), Time.FORMAT_SHORT);
        var todayDow = todayInfo.day_of_week as Number;  // 1=Sun..7=Sat
        for (var i = 0; i < 7; i++) {
            // Bar i is (6-i) days ago
            var dow = todayDow - (6 - i);
            while (dow < 1) {
                dow += 7;
            }
            var x = left + (i * (barW + gap)) + (barW / 2);
            dc.setColor(i == 6 ? COLOR_TEXT : COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, chartBottom + 4, Graphics.FONT_XTINY,
                        letters[dow - 1], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // ── Page 2: Insights ──────────────────────────────────────

    private function drawInsightsPage(dc as Dc) as Void {
        var hm = _historyManager;
        if (hm == null) { return; }

        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 20, Graphics.FONT_SMALL,
                    "Insights", Graphics.TEXT_JUSTIFY_CENTER);

        var y = 56;
        var missing = false;

        var peak = hm.getPeakHourWindow();
        if (peak < 0) { missing = true; }
        drawRecordRow(dc, y, "Peak hours",
                      peak >= 0 ? formatHour(peak) + "-" + formatHour((peak + 2) % 24) : "--",
                      peak >= 0 ? COLOR_FLOW : COLOR_TEXT_DIM);
        y += 28;

        var spot = hm.getSweetSpotBucket();
        if (spot < 0) { missing = true; }
        var spotLabels = ["<25m", "25-45m", "45-75m", "75m+"] as Array<String>;
        drawRecordRow(dc, y, "Best length",
                      spot >= 0 ? spotLabels[spot] : "--",
                      spot >= 0 ? COLOR_FLOW : COLOR_TEXT_DIM);
        y += 28;

        var rate = hm.getInterruptionRateTenths();
        if (rate < 0) { missing = true; }
        drawRecordRow(dc, y, "Break-ins",
                      rate >= 0 ? (rate / 10).format("%d") + "." + (rate % 10).format("%d") + "/h" : "--",
                      rate < 0 ? COLOR_TEXT_DIM : (rate <= 10 ? COLOR_FLOW : COLOR_TEXT));
        y += 28;

        var agree = hm.getRatingAgreement();
        if (agree < 0) { missing = true; }
        drawRecordRow(dc, y, "Watch vs you",
                      agree >= 0 ? agree.format("%d") + "% agree" : "--",
                      agree >= 0 ? COLOR_TEXT : COLOR_TEXT_DIM);
        y += 28;

        if (missing) {
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, y + 2, Graphics.FONT_XTINY,
                        "Sharpens with more sessions", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    //! Hour of day in the device's 12/24h style, compact
    private function formatHour(hour as Number) as String {
        if (System.getDeviceSettings().is24Hour) {
            return hour.format("%02d");
        }
        var h = hour % 12;
        if (h == 0) { h = 12; }
        return h.format("%d") + (hour < 12 ? "a" : "p");
    }

    // ── Page 3: Records ───────────────────────────────────────

    private function drawRecordsPage(dc as Dc) as Void {
        var hm = _historyManager;
        if (hm == null) { return; }

        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 20, Graphics.FONT_SMALL,
                    "Records", Graphics.TEXT_JUSTIFY_CENTER);

        var y = 56;

        var streak = hm.getCurrentStreakDays();
        drawRecordRow(dc, y, "Streak",
                      streak.format("%d") + (streak == 1 ? " day" : " days"),
                      streak > 0 ? COLOR_FLOW : COLOR_TEXT_DIM);
        y += 28;

        drawRecordRow(dc, y, "Best deep day",
                      hm.formatDurationCompact(hm.getBestDeepDay()), COLOR_TIME);
        y += 28;

        var bestQuality = hm.getBestQuality();
        drawRecordRow(dc, y, "Best quality",
                      bestQuality > 0 ? bestQuality.format("%d") : "--",
                      bestQuality >= 70 ? COLOR_FLOW : COLOR_TEXT);
        y += 28;

        var longest = hm.getLongestBlockEver();
        drawRecordRow(dc, y, "Longest block",
                      longest > 0 ? (longest / 60).format("%d") + " min" : "--", COLOR_TEXT);
        y += 28;

        drawRecordRow(dc, y, "All-time deep",
                      hm.formatDurationCompact(hm.getTotalDeepTime()), COLOR_TEXT);
    }

    private function drawRecordRow(dc as Dc, y as Number, label as String,
                                   value as String, valueColor as Number) as Void {
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(44, y, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_screenWidth - 44, y, Graphics.FONT_XTINY,
                    value, Graphics.TEXT_JUSTIFY_RIGHT);
    }
}

//! Stats view input delegate: UP/DOWN switch pages, BACK exits
class StatsDelegate extends WatchUi.BehaviorDelegate {

    private var _statsView as StatsView?;

    function initialize(statsView as StatsView?) {
        BehaviorDelegate.initialize();
        _statsView = statsView;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onPreviousPage() as Boolean {
        if (_statsView != null) {
            _statsView.prevPage();
        }
        return true;
    }

    function onNextPage() as Boolean {
        if (_statsView != null) {
            _statsView.nextPage();
        }
        return true;
    }
}

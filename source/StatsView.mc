import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

//! Stats: three pages navigated with UP/DOWN.
//! Page 0: Today — totals, mode breakdown, session list
//! Page 1: Week — 7-day focus bar chart
//! Page 2: Records — streak and personal bests
class StatsView extends WatchUi.View {

    private var _historyManager as HistoryManager?;
    private var _page as Number = 0;

    private const PAGE_COUNT = 3;

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
        var startX = _centerX - spacing;
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

        var todaySessions = hm.getTodaySessions();
        if (todaySessions.size() == 0) {
            drawCenteredNote(dc, "No sessions today");
            return;
        }

        // Total focus time
        var todayTime = hm.getTodayFocusTime();
        dc.setColor(COLOR_TIME, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 44, Graphics.FONT_MEDIUM,
                    hm.formatDuration(todayTime), Graphics.TEXT_JUSTIFY_CENTER);

        // Average flow score
        var y = 76;
        var avgFlow = hm.getTodayAvgFlowScore();
        if (avgFlow > 0) {
            var flowColor = avgFlow >= 70 ? COLOR_FLOW : (avgFlow >= 40 ? COLOR_POMO : COLOR_TEXT_DIM);
            dc.setColor(flowColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, y, Graphics.FONT_XTINY,
                        "Avg flow " + avgFlow.format("%d"), Graphics.TEXT_JUSTIFY_CENTER);
            y += 18;
        }

        // Mode breakdown
        var flowSessions = hm.getTodaySessionsByMode(MODE_FLOWTIMER);
        var pomoSessions = hm.getTodaySessionsByMode(MODE_POMODORO);

        if (flowSessions.size() > 0) {
            var flowTime = hm.getTodayFocusTimeByMode(MODE_FLOWTIMER);
            dc.setColor(COLOR_FLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, y, Graphics.FONT_XTINY,
                        "Flow: " + hm.formatDurationCompact(flowTime) + " (" + flowSessions.size() + ")",
                        Graphics.TEXT_JUSTIFY_CENTER);
            y += 18;
        }

        if (pomoSessions.size() > 0) {
            var pomoTime = hm.getTodayFocusTimeByMode(MODE_POMODORO);
            var cycles = hm.getTodayCompletedCycles();
            var cycleText = cycles > 0 ? ", " + cycles + " cyc" : "";
            dc.setColor(COLOR_POMO, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, y, Graphics.FONT_XTINY,
                        "Pomo: " + hm.formatDurationCompact(pomoTime) + " (" + pomoSessions.size() + ")" + cycleText,
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
            drawSessionRow(dc, todaySessions[i] as Dictionary, listY, i + 1);
            listY += SESSION_ROW_H;
        }

        if (todaySessions.size() > MAX_VISIBLE) {
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, listY, Graphics.FONT_XTINY,
                        "+" + (todaySessions.size() - MAX_VISIBLE).format("%d") + " more",
                        Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    private function drawSessionRow(dc as Dc, session as Dictionary, y as Number, index as Number) as Void {
        var timestamp = session.hasKey("timestamp") ? (session["timestamp"] as Number) : 0;
        var duration  = session.hasKey("duration")  ? (session["duration"]  as Number) : 0;

        var hm = _historyManager;
        var mode = (hm != null) ? hm.getSessionMode(session) : MODE_POMODORO;
        var modeChar = mode == MODE_FLOWTIMER ? "F" : "P";
        var modeColor = mode == MODE_FLOWTIMER ? COLOR_FLOW : COLOR_POMO;

        var converted = session.hasKey("converted") && (session["converted"] as Boolean);

        var moment = new Time.Moment(timestamp);
        var info   = Gregorian.info(moment, Time.FORMAT_SHORT);
        var timeStr = info.hour.format("%02d") + ":" + info.min.format("%02d");

        var durationStr = (hm != null) ? hm.formatDurationCompact(duration) : "0m";

        // Left: mode + time; middle: avg flow; right: duration
        dc.setColor(modeColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(32, y, Graphics.FONT_XTINY, modeChar, Graphics.TEXT_JUSTIFY_LEFT);

        var leftText = timeStr;
        if (converted) {
            leftText = leftText + "*";
        }
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(46, y, Graphics.FONT_XTINY, leftText, Graphics.TEXT_JUSTIFY_LEFT);

        // Session avg flow score, when biometrics were recorded
        if (session.hasKey("avgFlowScore") && session.hasKey("samples") &&
            (session["samples"] as Number) > 0) {
            var score = session["avgFlowScore"] as Number;
            var scoreColor = score >= 70 ? COLOR_FLOW : (score >= 40 ? COLOR_POMO : COLOR_TEXT_DIM);
            dc.setColor(scoreColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX + 28, y, Graphics.FONT_XTINY,
                        score.format("%d"), Graphics.TEXT_JUSTIFY_CENTER);
        }

        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_screenWidth - 32, y, Graphics.FONT_XTINY,
                    durationStr, Graphics.TEXT_JUSTIFY_RIGHT);
    }

    // ── Page 1: Week ──────────────────────────────────────────

    private function drawWeekPage(dc as Dc) as Void {
        var hm = _historyManager;
        if (hm == null) { return; }

        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 20, Graphics.FONT_SMALL,
                    "Last 7 Days", Graphics.TEXT_JUSTIFY_CENTER);

        var days = hm.getLast7DayFocus();

        var weekTotal = 0;
        var maxDay = 0;
        for (var i = 0; i < days.size(); i++) {
            weekTotal += days[i];
            if (days[i] > maxDay) {
                maxDay = days[i];
            }
        }

        dc.setColor(COLOR_TIME, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 44, Graphics.FONT_MEDIUM,
                    hm.formatDurationCompact(weekTotal), Graphics.TEXT_JUSTIFY_CENTER);

        if (weekTotal == 0) {
            drawCenteredNote(dc, "No sessions yet");
            return;
        }

        // Bar chart
        var barW = 16;
        var gap = 8;
        var chartW = (7 * barW) + (6 * gap);
        var left = _centerX - (chartW / 2);
        var chartBottom = 178;
        var maxBarH = 80;

        for (var i = 0; i < 7; i++) {
            var x = left + (i * (barW + gap));
            var barH = 0;
            if (maxDay > 0) {
                barH = (days[i] * maxBarH) / maxDay;
            }
            if (days[i] > 0 && barH < 3) {
                barH = 3;
            }

            if (barH > 0) {
                // Today (rightmost) highlighted in teal
                dc.setColor(i == 6 ? COLOR_FLOW : COLOR_BAR_DIM, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x, chartBottom - barH, barW, barH);
            } else {
                dc.setColor(COLOR_INACTIVE, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x, chartBottom - 2, barW, 2);
            }
        }

        // Day-of-week letters under the bars
        var letters = ["S", "M", "T", "W", "T", "F", "S"] as Array<String>;
        var todayInfo = Gregorian.info(Time.today(), Time.FORMAT_SHORT);
        var todayDow = todayInfo.day_of_week as Number;  // 1=Sun..7=Sat
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 7; i++) {
            // Bar i is (6-i) days ago
            var dow = todayDow - (6 - i);
            while (dow < 1) {
                dow += 7;
            }
            var x = left + (i * (barW + gap)) + (barW / 2);
            dc.drawText(x, chartBottom + 6, Graphics.FONT_XTINY,
                        letters[dow - 1], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // ── Page 2: Records ───────────────────────────────────────

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

        drawRecordRow(dc, y, "Best day",
                      hm.formatDurationCompact(hm.getBestDayFocusTime()), COLOR_TIME);
        y += 28;

        var bestFlow = hm.getBestSessionFlowScore();
        drawRecordRow(dc, y, "Best flow",
                      bestFlow > 0 ? bestFlow.format("%d") : "--",
                      bestFlow >= 70 ? COLOR_FLOW : COLOR_TEXT);
        y += 28;

        drawRecordRow(dc, y, "Sessions",
                      hm.getSessionCount().format("%d"), COLOR_TEXT);
        y += 28;

        drawRecordRow(dc, y, "All time",
                      hm.formatDurationCompact(hm.getTotalFocusTime()), COLOR_TEXT);
    }

    private function drawRecordRow(dc as Dc, y as Number, label as String,
                                   value as String, valueColor as Number) as Void {
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(50, y, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_screenWidth - 50, y, Graphics.FONT_XTINY,
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

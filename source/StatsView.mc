import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

//! Today's unified stats view with mode breakdown and scrollable session list
class StatsView extends WatchUi.View {

    private var _historyManager as HistoryManager?;
    private var _scrollOffset as Number = 0;

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

    private const SESSION_ROW_H  = 30;
    private const MAX_VISIBLE    = 3;

    function initialize(historyManager as HistoryManager?) {
        View.initialize();
        _historyManager = historyManager;
    }

    function onLayout(dc as Dc) as Void {
        _screenWidth  = dc.getWidth();
        _screenHeight = dc.getHeight();
        _centerX = _screenWidth  / 2;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        if (_historyManager == null) {
            drawNoData(dc);
            return;
        }

        var todaySessions = _historyManager.getTodaySessions();
        if (todaySessions.size() == 0) {
            drawNoData(dc);
            return;
        }

        drawStats(dc, todaySessions);
    }

    private function drawNoData(dc as Dc) as Void {
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _screenHeight / 2, Graphics.FONT_MEDIUM,
                    "No sessions today", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawStats(dc as Dc, todaySessions as Array<Dictionary>) as Void {
        var hm = _historyManager;
        if (hm == null) { return; }

        // Title
        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 22, Graphics.FONT_SMALL,
                    "Today", Graphics.TEXT_JUSTIFY_CENTER);

        // Total focus time
        var todayTime = hm.getTodayFocusTime();
        dc.setColor(COLOR_TIME, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 48, Graphics.FONT_MEDIUM,
                    hm.formatDuration(todayTime), Graphics.TEXT_JUSTIFY_CENTER);

        // Mode breakdown
        var flowSessions = hm.getTodaySessionsByMode(MODE_FLOWTIMER);
        var pomoSessions = hm.getTodaySessionsByMode(MODE_POMODORO);

        var y = 80;
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
            var cycleText = cycles > 0 ? ", " + cycles + " cycles" : "";
            dc.setColor(COLOR_POMO, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, y, Graphics.FONT_XTINY,
                        "Pomo: " + hm.formatDurationCompact(pomoTime) + " (" + pomoSessions.size() + ")" + cycleText,
                        Graphics.TEXT_JUSTIFY_CENTER);
            y += 18;
        }

        // Divider
        var divY = y + 4;
        dc.setColor(0x444444, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(45, divY, _screenWidth - 45, divY);

        // Session list
        var listY = divY + 10;
        var endIndex = _scrollOffset + MAX_VISIBLE;
        if (endIndex > todaySessions.size()) {
            endIndex = todaySessions.size();
        }

        for (var i = _scrollOffset; i < endIndex; i++) {
            var session = todaySessions[i] as Dictionary;
            drawSessionRow(dc, session, listY, i + 1);
            listY += SESSION_ROW_H;
        }

        // Scroll indicators
        if (_scrollOffset > 0) {
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[_centerX - 8, divY + 4],
                            [_centerX + 8, divY + 4],
                            [_centerX, divY - 4]]);
        }
        if (endIndex < todaySessions.size()) {
            var arrowY = listY + 4;
            dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[_centerX - 8, arrowY],
                            [_centerX + 8, arrowY],
                            [_centerX, arrowY + 8]]);
        }
    }

    private function drawSessionRow(dc as Dc, session as Dictionary, y as Number, index as Number) as Void {
        var timestamp = session.hasKey("timestamp") ? (session["timestamp"] as Number) : 0;
        var duration  = session.hasKey("duration")  ? (session["duration"]  as Number) : 0;

        // Mode indicator
        var hm = _historyManager;
        var mode = (hm != null) ? hm.getSessionMode(session) : MODE_POMODORO;
        var modeChar = mode == MODE_FLOWTIMER ? "F" : "P";
        var modeColor = mode == MODE_FLOWTIMER ? COLOR_FLOW : COLOR_POMO;

        // Converted marker
        var converted = session.hasKey("converted") && (session["converted"] as Boolean);

        // Start time
        var moment = new Time.Moment(timestamp);
        var info   = Gregorian.info(moment, Time.FORMAT_SHORT);
        var timeStr = info.hour.format("%02d") + ":" + info.min.format("%02d");

        // Duration
        var durationStr = (hm != null) ? hm.formatDuration(duration as Number) : "0:00";

        // Left: mode + index + time
        dc.setColor(modeColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(25, y, Graphics.FONT_XTINY, modeChar, Graphics.TEXT_JUSTIFY_LEFT);

        var leftText = "#" + index.format("%d") + " " + timeStr;
        if (converted) {
            leftText = leftText + "*";
        }
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(38, y, Graphics.FONT_XTINY, leftText, Graphics.TEXT_JUSTIFY_LEFT);

        // Right: duration
        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_screenWidth - 30, y, Graphics.FONT_XTINY,
                    durationStr, Graphics.TEXT_JUSTIFY_RIGHT);
    }

    function scrollUp() as Void {
        if (_scrollOffset > 0) {
            _scrollOffset--;
            WatchUi.requestUpdate();
        }
    }

    function scrollDown() as Void {
        if (_historyManager != null) {
            var todaySessions = _historyManager.getTodaySessions();
            if (_scrollOffset + MAX_VISIBLE < todaySessions.size()) {
                _scrollOffset++;
                WatchUi.requestUpdate();
            }
        }
    }
}

//! Stats view input delegate
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
            _statsView.scrollUp();
        }
        return true;
    }

    function onNextPage() as Boolean {
        if (_statsView != null) {
            _statsView.scrollDown();
        }
        return true;
    }
}

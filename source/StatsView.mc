import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

//! View displaying session history and statistics
class StatsView extends WatchUi.View {

    private var _historyManager as HistoryManager?;

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
    private const COLOR_FLOW_HIGH = 0x44FF44;

    //! Constructor
    function initialize(historyManager as HistoryManager?) {
        View.initialize();
        _historyManager = historyManager;
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
        // Clear screen
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        if (_historyManager == null) {
            drawNoData(dc);
            return;
        }

        var sessionCount = _historyManager.getSessionCount();
        if (sessionCount == 0) {
            drawNoData(dc);
            return;
        }

        drawStats(dc);
    }

    //! Draw no data message
    private function drawNoData(dc as Dc) as Void {
        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY, Graphics.FONT_MEDIUM,
                    "No sessions yet", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Draw statistics
    private function drawStats(dc as Dc) as Void {
        // Title
        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 25, Graphics.FONT_SMALL,
                    "Focus Stats", Graphics.TEXT_JUSTIFY_CENTER);

        // Today's stats
        var todayTime = _historyManager.getTodayFocusTime();
        var todaySessions = _historyManager.getTodaySessions();

        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 55, Graphics.FONT_TINY, "Today", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(COLOR_FLOW_HIGH, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 75, Graphics.FONT_MEDIUM,
                    _historyManager.formatDuration(todayTime), Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(COLOR_TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 100, Graphics.FONT_TINY,
                    todaySessions.size().format("%d") + " sessions", Graphics.TEXT_JUSTIFY_CENTER);

        // Divider
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(50, 120, _screenWidth - 50, 120);

        // All-time stats
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, 135, Graphics.FONT_TINY, "All Time", Graphics.TEXT_JUSTIFY_CENTER);

        var totalTime = _historyManager.getTotalFocusTime();
        var avgFlow = _historyManager.getOverallAvgFlowScore();
        var bestFlow = _historyManager.getBestFlowScore();
        var totalSessions = _historyManager.getSessionCount();

        // Total time
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(30, 160, Graphics.FONT_XTINY, "Total:", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_screenWidth - 30, 160, Graphics.FONT_XTINY,
                    _historyManager.formatDuration(totalTime), Graphics.TEXT_JUSTIFY_RIGHT);

        // Sessions count
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(30, 180, Graphics.FONT_XTINY, "Sessions:", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_screenWidth - 30, 180, Graphics.FONT_XTINY,
                    totalSessions.format("%d"), Graphics.TEXT_JUSTIFY_RIGHT);

        // Average flow
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(30, 200, Graphics.FONT_XTINY, "Avg Flow:", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(COLOR_FLOW_HIGH, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_screenWidth - 30, 200, Graphics.FONT_XTINY,
                    avgFlow.format("%d"), Graphics.TEXT_JUSTIFY_RIGHT);

        // Best flow
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(30, 220, Graphics.FONT_XTINY, "Best Flow:", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(COLOR_FLOW_HIGH, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_screenWidth - 30, 220, Graphics.FONT_XTINY,
                    bestFlow.format("%d"), Graphics.TEXT_JUSTIFY_RIGHT);
    }
}

//! Stats view input delegate
class StatsDelegate extends WatchUi.BehaviorDelegate {

    //! Constructor
    function initialize() {
        BehaviorDelegate.initialize();
    }

    //! Handle back button
    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    //! Handle select button - show session list
    function onSelect() as Boolean {
        var historyManager = getApp().getHistoryManager();
        if (historyManager != null && historyManager.getSessionCount() > 0) {
            var listView = new SessionListView(historyManager);
            var listDelegate = new SessionListDelegate(historyManager);
            WatchUi.pushView(listView, listDelegate, WatchUi.SLIDE_LEFT);
        }
        return true;
    }
}

//! View showing list of individual sessions
class SessionListView extends WatchUi.View {

    private var _historyManager as HistoryManager?;
    private var _scrollOffset as Number = 0;
    private const ITEMS_PER_PAGE = 4;

    //! Constructor
    function initialize(historyManager as HistoryManager?) {
        View.initialize();
        _historyManager = historyManager;
    }

    //! Update the view
    function onUpdate(dc as Dc) as Void {
        dc.setColor(0x000000, 0x000000);
        dc.clear();

        if (_historyManager == null) {
            return;
        }

        var sessions = _historyManager.getSessions();
        if (sessions == null || sessions.size() == 0) {
            return;
        }

        // Title
        dc.setColor(0x44AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, 20, Graphics.FONT_SMALL,
                    "Sessions", Graphics.TEXT_JUSTIFY_CENTER);

        // Draw session list
        var y = 50;
        var endIndex = _scrollOffset + ITEMS_PER_PAGE;
        if (endIndex > sessions.size()) {
            endIndex = sessions.size();
        }

        for (var i = _scrollOffset; i < endIndex; i++) {
            var session = sessions[i] as Dictionary;
            drawSessionItem(dc, session, y, i);
            y += 45;
        }

        // Scroll indicators
        if (_scrollOffset > 0) {
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[dc.getWidth() / 2 - 10, 40], [dc.getWidth() / 2 + 10, 40], [dc.getWidth() / 2, 30]]);
        }
        if (endIndex < sessions.size()) {
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[dc.getWidth() / 2 - 10, dc.getHeight() - 20], [dc.getWidth() / 2 + 10, dc.getHeight() - 20], [dc.getWidth() / 2, dc.getHeight() - 10]]);
        }
    }

    //! Draw a single session item
    private function drawSessionItem(dc as Dc, session as Dictionary, y as Number, index as Number) as Void {
        var timestamp = session.hasKey("timestamp") ? session["timestamp"] : 0;
        var duration = session.hasKey("duration") ? session["duration"] : 0;
        var avgFlow = session.hasKey("avgFlowScore") ? session["avgFlowScore"] : 0;

        // Format date
        var moment = new Time.Moment(timestamp);
        var info = Gregorian.info(moment, Time.FORMAT_SHORT);
        var dateStr = info.month.format("%02d") + "/" + info.day.format("%02d");

        // Duration
        var durationStr = _historyManager.formatDuration(duration);

        // Draw
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(30, y, Graphics.FONT_TINY, dateStr, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, y, Graphics.FONT_TINY, durationStr, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(0x44FF44, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() - 30, y, Graphics.FONT_TINY,
                    "F:" + avgFlow.format("%d"), Graphics.TEXT_JUSTIFY_RIGHT);
    }

    //! Scroll up
    function scrollUp() as Void {
        if (_scrollOffset > 0) {
            _scrollOffset--;
            WatchUi.requestUpdate();
        }
    }

    //! Scroll down
    function scrollDown() as Void {
        if (_historyManager != null) {
            var sessions = _historyManager.getSessions();
            if (sessions != null && _scrollOffset + ITEMS_PER_PAGE < sessions.size()) {
                _scrollOffset++;
                WatchUi.requestUpdate();
            }
        }
    }
}

//! Session list input delegate
class SessionListDelegate extends WatchUi.BehaviorDelegate {

    private var _historyManager as HistoryManager?;
    private var _listView as SessionListView?;

    //! Constructor
    function initialize(historyManager as HistoryManager?) {
        BehaviorDelegate.initialize();
        _historyManager = historyManager;
    }

    //! Set the list view reference
    function setListView(view as SessionListView) as Void {
        _listView = view;
    }

    //! Handle back button
    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    //! Handle UP button
    function onPreviousPage() as Boolean {
        if (_listView != null) {
            _listView.scrollUp();
        }
        return true;
    }

    //! Handle DOWN button
    function onNextPage() as Boolean {
        if (_listView != null) {
            _listView.scrollDown();
        }
        return true;
    }
}

import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

//! Manages session history persistence using Storage API
class HistoryManager {

    private const HISTORY_KEY = "sessionHistory";
    private const MAX_SESSIONS = 50;

    private var _sessions as Array<Dictionary>?;

    //! Constructor
    function initialize() {
        loadHistory();
    }

    private function loadHistory() as Void {
        try {
            var data = Storage.getValue(HISTORY_KEY);
            if (data != null && data instanceof Array) {
                _sessions = data as Array<Dictionary>;
            } else {
                _sessions = [] as Array<Dictionary>;
            }
        } catch (ex) {
            System.println("Error loading history: " + ex.getErrorMessage());
            _sessions = [] as Array<Dictionary>;
        }
    }

    private function saveHistory() as Void {
        try {
            Storage.setValue(HISTORY_KEY, _sessions as Application.PropertyValueType);
        } catch (ex) {
            System.println("Error saving history: " + ex.getErrorMessage());
        }
    }

    //! Save a new session (newest first)
    function saveSession(session as Dictionary) as Void {
        if (_sessions == null) {
            _sessions = [] as Array<Dictionary>;
        }

        var newSessions = [session] as Array<Dictionary>;
        for (var i = 0; i < _sessions.size() && i < MAX_SESSIONS - 1; i++) {
            newSessions.add(_sessions[i]);
        }
        _sessions = newSessions;
        saveHistory();
    }

    function getSessions() as Array<Dictionary>? {
        return _sessions;
    }

    function getSessionCount() as Number {
        if (_sessions == null) {
            return 0;
        }
        return _sessions.size();
    }

    function getSession(index as Number) as Dictionary? {
        if (_sessions == null || index < 0 || index >= _sessions.size()) {
            return null;
        }
        return _sessions[index];
    }

    //! Get total focus time in seconds across all sessions
    function getTotalFocusTime() as Number {
        if (_sessions == null) {
            return 0;
        }
        var total = 0;
        for (var i = 0; i < _sessions.size(); i++) {
            var session = _sessions[i];
            if (session.hasKey("duration")) {
                total += (session["duration"] as Number);
            }
        }
        return total;
    }

    //! Get sessions from today
    function getTodaySessions() as Array<Dictionary> {
        var todaySessions = [] as Array<Dictionary>;
        if (_sessions == null) {
            return todaySessions;
        }

        var now = Time.now();
        var today = Gregorian.info(now, Time.FORMAT_SHORT);

        for (var i = 0; i < _sessions.size(); i++) {
            var session = _sessions[i];
            if (session.hasKey("timestamp")) {
                var sessionTime = new Time.Moment(session["timestamp"] as Number);
                var sessionDate = Gregorian.info(sessionTime, Time.FORMAT_SHORT);
                if (sessionDate.year == today.year &&
                    sessionDate.month == today.month &&
                    sessionDate.day == today.day) {
                    todaySessions.add(session);
                }
            }
        }
        return todaySessions;
    }

    //! Get today's sessions filtered by mode
    function getTodaySessionsByMode(mode as Number) as Array<Dictionary> {
        var todaySessions = getTodaySessions();
        var filtered = [] as Array<Dictionary>;
        for (var i = 0; i < todaySessions.size(); i++) {
            var session = todaySessions[i];
            var sessionMode = getSessionMode(session);
            if (sessionMode == mode) {
                filtered.add(session);
            }
        }
        return filtered;
    }

    //! Get mode from a session dict (defaults to MODE_POMODORO for legacy sessions)
    function getSessionMode(session as Dictionary) as Number {
        if (session.hasKey("mode")) {
            return session["mode"] as Number;
        }
        return MODE_POMODORO;  // Legacy sessions are Pomodoro
    }

    //! Get today's total focus time
    function getTodayFocusTime() as Number {
        var todaySessions = getTodaySessions();
        var total = 0;
        for (var i = 0; i < todaySessions.size(); i++) {
            var session = todaySessions[i];
            if (session.hasKey("duration")) {
                total += (session["duration"] as Number);
            }
        }
        return total;
    }

    //! Get today's focus time for a specific mode
    function getTodayFocusTimeByMode(mode as Number) as Number {
        var sessions = getTodaySessionsByMode(mode);
        var total = 0;
        for (var i = 0; i < sessions.size(); i++) {
            var session = sessions[i];
            if (session.hasKey("duration")) {
                total += (session["duration"] as Number);
            }
        }
        return total;
    }

    //! Get today's Pomodoro session count
    function getTodayPomodoroCount() as Number {
        return getTodaySessionsByMode(MODE_POMODORO).size();
    }

    //! Get today's completed Pomodoro cycles (every 4 sessions = 1 cycle)
    function getTodayCompletedCycles() as Number {
        return getTodayPomodoroCount() / 4;
    }

    //! Total focus seconds for the day N days ago (0 = today), local time
    function getFocusTimeForDaysAgo(daysAgo as Number) as Number {
        if (_sessions == null) {
            return 0;
        }
        var dayStart = Time.today().value() - (daysAgo * 86400);
        var dayEnd = dayStart + 86400;
        var total = 0;
        for (var i = 0; i < _sessions.size(); i++) {
            var session = _sessions[i];
            if (session.hasKey("timestamp") && session.hasKey("duration")) {
                var ts = session["timestamp"] as Number;
                if (ts >= dayStart && ts < dayEnd) {
                    total += (session["duration"] as Number);
                }
            }
        }
        return total;
    }

    //! Focus seconds per day for the last 7 days, oldest first
    function getLast7DayFocus() as Array<Number> {
        var days = [] as Array<Number>;
        for (var d = 6; d >= 0; d--) {
            days.add(getFocusTimeForDaysAgo(d));
        }
        return days;
    }

    //! Consecutive days (ending today or yesterday) with at least one session
    function getCurrentStreakDays() as Number {
        var streak = 0;
        // A streak is still alive if yesterday had a session, even when
        // today's first session hasn't happened yet
        var start = getFocusTimeForDaysAgo(0) > 0 ? 0 : 1;
        for (var d = start; d < 365; d++) {
            if (getFocusTimeForDaysAgo(d) > 0) {
                streak++;
            } else {
                break;
            }
        }
        return streak;
    }

    // ── Deep-work analytics ───────────────────────────────────
    // Sessions saved before the deep-work engine have no "quality" key;
    // they still count toward focus time but are left out of depth stats.

    //! Numeric field from a session, or a default when missing
    function sessionNum(session as Dictionary, key as String, fallback as Number) as Number {
        if (session.hasKey(key) && session[key] instanceof Number) {
            return session[key] as Number;
        }
        return fallback;
    }

    function hasQuality(session as Dictionary) as Boolean {
        if (!session.hasKey("quality")) {
            return false;
        }
        if (session["quality"] instanceof Number) {
            return true;
        }
        return false;
    }

    //! Deep seconds for the day N days ago (0 = today), local time
    function getDeepTimeForDaysAgo(daysAgo as Number) as Number {
        if (_sessions == null) {
            return 0;
        }
        var dayStart = Time.today().value() - (daysAgo * 86400);
        var dayEnd = dayStart + 86400;
        var total = 0;
        for (var i = 0; i < _sessions.size(); i++) {
            var session = _sessions[i];
            var ts = sessionNum(session, "timestamp", 0);
            if (ts >= dayStart && ts < dayEnd) {
                total += sessionNum(session, "deepSec", 0);
            }
        }
        return total;
    }

    function getTodayDeepTime() as Number {
        return getDeepTimeForDaysAgo(0);
    }

    //! Deep seconds per day for the last 7 days, oldest first
    function getLast7DayDeep() as Array<Number> {
        var days = [] as Array<Number>;
        for (var d = 6; d >= 0; d--) {
            days.add(getDeepTimeForDaysAgo(d));
        }
        return days;
    }

    //! Duration-weighted average quality of the given sessions (-1 = none)
    function avgQuality(sessions as Array<Dictionary>) as Number {
        var weighted = 0;
        var total = 0;
        for (var i = 0; i < sessions.size(); i++) {
            var session = sessions[i];
            if (hasQuality(session)) {
                var minutes = sessionNum(session, "duration", 0) / 60;
                weighted += sessionNum(session, "quality", 0) * minutes;
                total += minutes;
            }
        }
        return total > 0 ? weighted / total : -1;
    }

    function getTodayAvgQuality() as Number {
        return avgQuality(getTodaySessions());
    }

    function getTodayInterruptions() as Number {
        var todaySessions = getTodaySessions();
        var total = 0;
        for (var i = 0; i < todaySessions.size(); i++) {
            total += sessionNum(todaySessions[i], "intr", 0);
        }
        return total;
    }

    //! Sessions with a quality score from the last N days
    private function recentQualitySessions(days as Number) as Array<Dictionary> {
        var result = [] as Array<Dictionary>;
        if (_sessions == null) {
            return result;
        }
        var cutoff = Time.today().value() - ((days - 1) * 86400);
        for (var i = 0; i < _sessions.size(); i++) {
            var session = _sessions[i];
            if (hasQuality(session) && sessionNum(session, "timestamp", 0) >= cutoff) {
                result.add(session);
            }
        }
        return result;
    }

    //! Interruptions per focused hour over the last 7 days, in tenths
    //! (e.g. 23 = 2.3/h). -1 when there is no data.
    function getInterruptionRateTenths() as Number {
        var sessions = recentQualitySessions(7);
        var intr = 0;
        var seconds = 0;
        for (var i = 0; i < sessions.size(); i++) {
            intr += sessionNum(sessions[i], "intr", 0);
            seconds += sessionNum(sessions[i], "duration", 0);
        }
        if (seconds < 600) {
            return -1;
        }
        return (intr * 36000) / seconds;
    }

    //! Start hour of the 2-hour window with the best average quality,
    //! or -1 until there is enough data (>= 2 sessions in the window).
    //! Single pass: Gregorian.info is too slow to call per bucket.
    function getPeakHourWindow() as Number {
        if (_sessions == null) {
            return -1;
        }
        var weighted = [] as Array<Number>;
        var minutes  = [] as Array<Number>;
        var counts   = [] as Array<Number>;
        for (var k = 0; k < 12; k++) {
            weighted.add(0);
            minutes.add(0);
            counts.add(0);
        }
        for (var i = 0; i < _sessions.size(); i++) {
            var session = _sessions[i];
            if (!hasQuality(session)) {
                continue;
            }
            var info = Gregorian.info(new Time.Moment(sessionNum(session, "timestamp", 0)),
                                      Time.FORMAT_SHORT);
            var slot = (info.hour as Number) / 2;
            var m = sessionNum(session, "duration", 0) / 60;
            weighted[slot] += sessionNum(session, "quality", 0) * m;
            minutes[slot] += m;
            counts[slot] += 1;
        }
        var bestHour = -1;
        var bestQuality = -1;
        for (var w = 0; w < 12; w++) {
            if (counts[w] >= 2 && minutes[w] > 0) {
                var q = weighted[w] / minutes[w];
                if (q > bestQuality) {
                    bestQuality = q;
                    bestHour = w * 2;
                }
            }
        }
        return bestHour;
    }

    //! Duration bucket with the best average quality, or -1 until there is
    //! enough data. 0: <25 min, 1: 25-44, 2: 45-74, 3: 75+
    function getSweetSpotBucket() as Number {
        if (_sessions == null) {
            return -1;
        }
        var bestBucket = -1;
        var bestQuality = -1;
        for (var b = 0; b < 4; b++) {
            var bucket = [] as Array<Dictionary>;
            for (var i = 0; i < _sessions.size(); i++) {
                var session = _sessions[i];
                if (hasQuality(session) &&
                    durationBucket(sessionNum(session, "duration", 0)) == b) {
                    bucket.add(session);
                }
            }
            if (bucket.size() >= 2) {
                var q = avgQuality(bucket);
                if (q > bestQuality) {
                    bestQuality = q;
                    bestBucket = b;
                }
            }
        }
        return bestBucket;
    }

    private function durationBucket(seconds as Number) as Number {
        var minutes = seconds / 60;
        if (minutes < 25) { return 0; }
        if (minutes < 45) { return 1; }
        if (minutes < 75) { return 2; }
        return 3;
    }

    //! How often the watch's verdict matches your own rating (percent),
    //! or -1 with fewer than 3 rated sessions
    function getRatingAgreement() as Number {
        if (_sessions == null) {
            return -1;
        }
        var rated = 0;
        var agree = 0;
        for (var i = 0; i < _sessions.size(); i++) {
            var session = _sessions[i];
            var rating = sessionNum(session, "rating", 0);
            if (rating > 0 && hasQuality(session)) {
                rated++;
                if (qualityToRating(sessionNum(session, "quality", 0)) == rating) {
                    agree++;
                }
            }
        }
        return rated >= 3 ? (agree * 100) / rated : -1;
    }

    //! Map a quality score onto the 3-step self-rating scale
    function qualityToRating(quality as Number) as Number {
        if (quality >= 70) { return 3; }
        if (quality >= 40) { return 2; }
        return 1;
    }

    //! Attach a self-rating (1 shallow .. 3 deep) to the session that
    //! started at the given timestamp
    function setSelfRating(timestamp as Number, rating as Number) as Void {
        if (_sessions == null) {
            return;
        }
        for (var i = 0; i < _sessions.size(); i++) {
            var session = _sessions[i];
            if (sessionNum(session, "timestamp", -1) == timestamp) {
                session["rating"] = rating;
                saveHistory();
                return;
            }
        }
    }

    //! Best single day of deep time (last ~30 days)
    function getBestDeepDay() as Number {
        var best = 0;
        for (var d = 0; d < 30; d++) {
            var dayTotal = getDeepTimeForDaysAgo(d);
            if (dayTotal > best) {
                best = dayTotal;
            }
        }
        return best;
    }

    function getBestQuality() as Number {
        return maxField("quality");
    }

    function getLongestBlockEver() as Number {
        return maxField("longest");
    }

    private function maxField(key as String) as Number {
        if (_sessions == null) {
            return 0;
        }
        var best = 0;
        for (var i = 0; i < _sessions.size(); i++) {
            var value = sessionNum(_sessions[i], key, 0);
            if (value > best) {
                best = value;
            }
        }
        return best;
    }

    function getTotalDeepTime() as Number {
        if (_sessions == null) {
            return 0;
        }
        var total = 0;
        for (var i = 0; i < _sessions.size(); i++) {
            total += sessionNum(_sessions[i], "deepSec", 0);
        }
        return total;
    }

    //! Format duration as HH:MM:SS or MM:SS
    function formatDuration(seconds as Number) as String {
        var hours = seconds / 3600;
        var minutes = (seconds % 3600) / 60;
        var secs = seconds % 60;
        if (hours > 0) {
            return hours.format("%d") + ":" + minutes.format("%02d") + ":" + secs.format("%02d");
        } else {
            return minutes.format("%02d") + ":" + secs.format("%02d");
        }
    }

    //! Format duration as compact "Xh XXm" for stats
    function formatDurationCompact(seconds as Number) as String {
        var hours = seconds / 3600;
        var minutes = (seconds % 3600) / 60;
        if (hours > 0) {
            return hours.format("%d") + "h " + minutes.format("%02d") + "m";
        } else {
            return minutes.format("%d") + "m";
        }
    }

    function clearHistory() as Void {
        _sessions = [] as Array<Dictionary>;
        saveHistory();
    }

    function deleteSession(index as Number) as Void {
        if (_sessions == null || index < 0 || index >= _sessions.size()) {
            return;
        }
        var newSessions = [] as Array<Dictionary>;
        for (var i = 0; i < _sessions.size(); i++) {
            if (i != index) {
                newSessions.add(_sessions[i]);
            }
        }
        _sessions = newSessions;
        saveHistory();
    }
}

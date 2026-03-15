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

    //! Get average flow score across all sessions (weighted by samples)
    function getOverallAvgFlowScore() as Number {
        if (_sessions == null || _sessions.size() == 0) {
            return 0;
        }
        var totalWeighted = 0;
        var totalSamples = 0;
        for (var i = 0; i < _sessions.size(); i++) {
            var session = _sessions[i];
            if (session.hasKey("avgFlowScore") && session.hasKey("samples")) {
                totalWeighted += (session["avgFlowScore"] as Number) * (session["samples"] as Number);
                totalSamples += (session["samples"] as Number);
            }
        }
        if (totalSamples == 0) {
            return 0;
        }
        return totalWeighted / totalSamples;
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

    //! Get today's average flow score (weighted by samples)
    function getTodayAvgFlowScore() as Number {
        var todaySessions = getTodaySessions();
        if (todaySessions.size() == 0) {
            return 0;
        }
        var totalWeighted = 0;
        var totalSamples = 0;
        for (var i = 0; i < todaySessions.size(); i++) {
            var session = todaySessions[i];
            if (session.hasKey("avgFlowScore") && session.hasKey("samples")) {
                totalWeighted += (session["avgFlowScore"] as Number) * (session["samples"] as Number);
                totalSamples += (session["samples"] as Number);
            }
        }
        if (totalSamples == 0) {
            return 0;
        }
        return totalWeighted / totalSamples;
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

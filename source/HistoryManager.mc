import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

//! Manages session history persistence using Storage API
class HistoryManager {

    private const HISTORY_KEY = "sessionHistory";
    private const MAX_SESSIONS = 50;  // Limit to stay within 32KB

    private var _sessions as Array<Dictionary>?;

    //! Constructor
    function initialize() {
        loadHistory();
    }

    //! Load session history from storage
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

    //! Save session history to storage
    private function saveHistory() as Void {
        try {
            Storage.setValue(HISTORY_KEY, _sessions as Application.PropertyValueType);
        } catch (ex) {
            System.println("Error saving history: " + ex.getErrorMessage());
        }
    }

    //! Save a new session
    function saveSession(session as Dictionary) as Void {
        if (_sessions == null) {
            _sessions = [] as Array<Dictionary>;
        }

        // Add session to beginning (newest first)
        var newSessions = [session] as Array<Dictionary>;
        for (var i = 0; i < _sessions.size() && i < MAX_SESSIONS - 1; i++) {
            newSessions.add(_sessions[i]);
        }
        _sessions = newSessions;

        saveHistory();
    }

    //! Get all sessions (newest first)
    function getSessions() as Array<Dictionary>? {
        return _sessions;
    }

    //! Get session count
    function getSessionCount() as Number {
        if (_sessions == null) {
            return 0;
        }
        return _sessions.size();
    }

    //! Get a specific session by index
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

    //! Get average flow score across all sessions
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

    //! Get best flow score from any session
    function getBestFlowScore() as Number {
        if (_sessions == null || _sessions.size() == 0) {
            return 0;
        }

        var best = 0;
        for (var i = 0; i < _sessions.size(); i++) {
            var session = _sessions[i];
            if (session.hasKey("avgFlowScore")) {
                var score = session["avgFlowScore"] as Number;
                if (score > best) {
                    best = score;
                }
            }
        }
        return best;
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

    //! Clear all history
    function clearHistory() as Void {
        _sessions = [] as Array<Dictionary>;
        saveHistory();
    }

    //! Delete a specific session by index
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

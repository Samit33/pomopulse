import Toybox.Application;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;

//! Timer states
enum TimerState {
    STATE_IDLE,
    STATE_WORK,
    STATE_WORK_PAUSED,
    STATE_BREAK,
    STATE_BREAK_PAUSED
}

//! Controls the Pomodoro timer state machine
class TimerController {

    // Default durations in seconds
    private const DEFAULT_WORK_DURATION = 25 * 60;  // 25 minutes
    private const DEFAULT_SHORT_BREAK = 5 * 60;     // 5 minutes
    private const DEFAULT_LONG_BREAK = 15 * 60;     // 15 minutes
    private const POMODOROS_UNTIL_LONG_BREAK = 4;

    private var _timer as Timer.Timer?;
    private var _state as TimerState = STATE_IDLE;
    private var _remainingSeconds as Number = 0;
    private var _totalSeconds as Number = 0;
    private var _pomodorosCompleted as Number = 0;
    private var _callback as Method?;
    private var _workCompleteCallback as Method?;

    // Configurable durations
    private var _workDuration as Number;
    private var _shortBreakDuration as Number;
    private var _longBreakDuration as Number;
    private var _autoStartBreak as Boolean = false;

    //! Constructor
    function initialize() {
        _workDuration = loadSetting("workDuration", DEFAULT_WORK_DURATION) as Number;
        _shortBreakDuration = loadSetting("shortBreakDuration", DEFAULT_SHORT_BREAK) as Number;
        _longBreakDuration = loadSetting("longBreakDuration", DEFAULT_LONG_BREAK) as Number;
        _autoStartBreak = loadSetting("autoStartBreak", false) as Boolean;
        resetToWork();
    }

    //! Load a setting with default fallback
    private function loadSetting(key as String, defaultValue as Application.PropertyValueType) as Application.PropertyValueType {
        var value = Application.Properties.getValue(key);
        if (value != null) {
            return value;
        }
        return defaultValue;
    }

    //! Set the tick callback for UI updates
    function setCallback(callback as Method?) as Void {
        _callback = callback;
    }

    //! Set callback for when work phase completes naturally
    function setWorkCompleteCallback(callback as Method?) as Void {
        _workCompleteCallback = callback;
    }

    //! Start the timer
    function start() as Void {
        if (_state == STATE_IDLE || _state == STATE_WORK_PAUSED) {
            _state = STATE_WORK;
            startTimer();
        } else if (_state == STATE_BREAK_PAUSED) {
            _state = STATE_BREAK;
            startTimer();
        }
    }

    //! Pause the timer
    function pause() as Void {
        if (_state == STATE_WORK) {
            _state = STATE_WORK_PAUSED;
            stopTimer();
        } else if (_state == STATE_BREAK) {
            _state = STATE_BREAK_PAUSED;
            stopTimer();
        }
    }

    //! Toggle between start and pause
    function toggle() as Void {
        if (isRunning()) {
            pause();
        } else {
            start();
        }
    }

    //! Reset the timer to work state
    function resetToWork() as Void {
        stopTimer();
        _state = STATE_IDLE;
        _remainingSeconds = _workDuration;
        _totalSeconds = _workDuration;
    }

    //! Reset the timer completely including pomodoro count
    function resetAll() as Void {
        resetToWork();
        _pomodorosCompleted = 0;
    }

    //! Skip to break
    function skipToBreak() as Void {
        stopTimer();
        _pomodorosCompleted++;
        startBreak();
    }

    //! Skip break and start work
    function skipToWork() as Void {
        resetToWork();
    }

    //! Start the internal timer
    private function startTimer() as Void {
        if (_timer == null) {
            _timer = new Timer.Timer();
        }
        _timer.start(method(:onTick), 1000, true);
    }

    //! Stop the internal timer
    private function stopTimer() as Void {
        if (_timer != null) {
            _timer.stop();
        }
    }

    //! Timer tick callback (called every second)
    function onTick() as Void {
        if (_remainingSeconds > 0) {
            _remainingSeconds--;

            if (_callback != null) {
                _callback.invoke();
            }
        }

        if (_remainingSeconds <= 0) {
            onTimerComplete();
        }
    }

    //! Handle timer completion
    private function onTimerComplete() as Void {
        stopTimer();
        vibrate();

        if (_state == STATE_WORK) {
            _pomodorosCompleted++;

            // Notify that work phase completed (triggers session summary)
            if (_workCompleteCallback != null) {
                _workCompleteCallback.invoke();
            }

            if (_autoStartBreak) {
                startBreak();
            } else {
                _state = STATE_IDLE;
                startBreak();
                _state = STATE_BREAK_PAUSED;
            }
        } else if (_state == STATE_BREAK) {
            resetToWork();
        }

        if (_callback != null) {
            _callback.invoke();
        }
    }

    //! Start a break period
    private function startBreak() as Void {
        var breakDuration;
        if (_pomodorosCompleted > 0 && _pomodorosCompleted % POMODOROS_UNTIL_LONG_BREAK == 0) {
            breakDuration = _longBreakDuration;
        } else {
            breakDuration = _shortBreakDuration;
        }

        _remainingSeconds = breakDuration;
        _totalSeconds = breakDuration;
        _state = STATE_BREAK;
        startTimer();
    }

    //! Trigger vibration alert
    function vibrate() as Void {
        if (Attention has :vibrate) {
            var vibeData = [
                new Attention.VibeProfile(100, 500),
                new Attention.VibeProfile(0, 200),
                new Attention.VibeProfile(100, 500)
            ] as Array<Attention.VibeProfile>;
            Attention.vibrate(vibeData);
        }
    }

    //! Get remaining time in seconds
    function getRemainingSeconds() as Number {
        return _remainingSeconds;
    }

    //! Get total time for current period
    function getTotalSeconds() as Number {
        return _totalSeconds;
    }

    //! Get elapsed time in seconds
    function getElapsedSeconds() as Number {
        return _totalSeconds - _remainingSeconds;
    }

    //! Get remaining time formatted as MM:SS
    function getRemainingTimeString() as String {
        var minutes = _remainingSeconds / 60;
        var seconds = _remainingSeconds % 60;
        return minutes.format("%02d") + ":" + seconds.format("%02d");
    }

    //! Get progress as percentage (0-100)
    function getProgress() as Number {
        if (_totalSeconds == 0) {
            return 0;
        }
        return (((_totalSeconds - _remainingSeconds) * 100) / _totalSeconds);
    }

    //! Check if timer is running
    function isRunning() as Boolean {
        return _state == STATE_WORK || _state == STATE_BREAK;
    }

    //! Check if in work state (running or paused)
    function isWorkState() as Boolean {
        return _state == STATE_IDLE || _state == STATE_WORK || _state == STATE_WORK_PAUSED;
    }

    //! Check if in break state (running or paused)
    function isBreakState() as Boolean {
        return _state == STATE_BREAK || _state == STATE_BREAK_PAUSED;
    }

    //! Get current state
    function getState() as TimerState {
        return _state;
    }

    //! Get state label for display
    function getStateLabel() as String {
        switch (_state) {
            case STATE_IDLE:
                return "Ready";
            case STATE_WORK:
                return "Focus";
            case STATE_WORK_PAUSED:
                return "Paused";
            case STATE_BREAK:
                return "Break";
            case STATE_BREAK_PAUSED:
                return "Break (Paused)";
            default:
                return "";
        }
    }

    //! Get number of completed pomodoros
    function getPomodorosCompleted() as Number {
        return _pomodorosCompleted;
    }

    //! Returns true if the current break is a long break
    function isLongBreak() as Boolean {
        return _totalSeconds == _longBreakDuration;
    }

    //! Update work duration setting
    function setWorkDuration(minutes as Number) as Void {
        _workDuration = minutes * 60;
        Application.Properties.setValue("workDuration", _workDuration);
        if (_state == STATE_IDLE) {
            resetToWork();
        }
    }

    //! Update short break duration setting
    function setShortBreakDuration(minutes as Number) as Void {
        _shortBreakDuration = minutes * 60;
        Application.Properties.setValue("shortBreakDuration", _shortBreakDuration);
    }

    //! Update long break duration setting
    function setLongBreakDuration(minutes as Number) as Void {
        _longBreakDuration = minutes * 60;
        Application.Properties.setValue("longBreakDuration", _longBreakDuration);
    }

    //! Update auto-start break setting
    function setAutoStartBreak(enabled as Boolean) as Void {
        _autoStartBreak = enabled;
        Application.Properties.setValue("autoStartBreak", enabled);
    }

    //! Get work duration in minutes
    function getWorkDurationMinutes() as Number {
        return _workDuration / 60;
    }

    //! Get short break duration in minutes
    function getShortBreakDurationMinutes() as Number {
        return _shortBreakDuration / 60;
    }

    //! Get long break duration in minutes
    function getLongBreakDurationMinutes() as Number {
        return _longBreakDuration / 60;
    }

    //! Get auto-start break setting
    function getAutoStartBreak() as Boolean {
        return _autoStartBreak;
    }
}

import Toybox.Application;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;

//! Timer modes
enum TimerMode {
    MODE_FLOWTIMER = 0,
    MODE_POMODORO = 1
}

//! Timer states
enum TimerState {
    STATE_IDLE,
    STATE_FLOW_RUNNING,    // Flowtimer: counting up
    STATE_FLOW_PAUSED,     // Flowtimer: paused (15-min timeout ticking)
    STATE_POMO_WORK,       // Pomodoro: counting down (no pause allowed)
    STATE_POMO_BREAK,      // Pomodoro: break running
    STATE_POMO_BREAK_WAIT  // Pomodoro: break ready (press START to begin)
}

//! Controls the dual-mode timer state machine (Flowtimer + Pomodoro)
class TimerController {

    // Flowtimer constants
    private const FLOW_PAUSE_TIMEOUT = 15 * 60;   // 15 minutes
    private const FLOW_NUDGE_TIME = 90 * 60;       // 90 minutes
    private const FLOW_CEILING_TIME = 120 * 60;    // 120 minutes

    // Pomodoro defaults
    private const DEFAULT_WORK_DURATION = 25 * 60;
    private const DEFAULT_SHORT_BREAK = 5 * 60;
    private const DEFAULT_LONG_BREAK = 15 * 60;
    private const SESSIONS_PER_CYCLE = 4;

    // Mode
    private var _mode as TimerMode = MODE_FLOWTIMER;

    // Timer internals
    private var _timer as Timer.Timer?;
    private var _state as TimerState = STATE_IDLE;
    private var _activeSeconds as Number = 0;        // Active time (both modes)
    private var _remainingSeconds as Number = 0;      // Countdown (Pomodoro only)
    private var _totalSeconds as Number = 0;          // Total phase duration (Pomodoro only)

    // Flowtimer pause tracking
    private var _pauseStartMoment as Time.Moment?;
    private var _nudgeFired as Boolean = false;

    // Pomodoro cycle tracking
    private var _cyclePosition as Number = 1;         // 1-4 within current cycle
    private var _pomodorosCompleted as Number = 0;     // Total today

    // Configurable Pomodoro durations
    private var _workDuration as Number;
    private var _shortBreakDuration as Number;
    private var _longBreakDuration as Number;

    // Callbacks
    private var _tickCallback as Method?;
    private var _workCompleteCallback as Method?;
    private var _autoStopCallback as Method?;
    private var _cycleCompleteCallback as Method?;

    //! Constructor
    function initialize() {
        _mode = loadSetting("timerMode", MODE_FLOWTIMER) as TimerMode;
        _workDuration = loadSetting("workDuration", DEFAULT_WORK_DURATION) as Number;
        _shortBreakDuration = loadSetting("shortBreakDuration", DEFAULT_SHORT_BREAK) as Number;
        _longBreakDuration = loadSetting("longBreakDuration", DEFAULT_LONG_BREAK) as Number;
        resetToIdle();
    }

    //! Load a setting with default fallback
    private function loadSetting(key as String, defaultValue as Application.PropertyValueType) as Application.PropertyValueType {
        var value = Application.Properties.getValue(key);
        if (value != null) {
            return value;
        }
        return defaultValue;
    }

    // ── Callbacks ──────────────────────────────────────────────

    function setTickCallback(callback as Method?) as Void {
        _tickCallback = callback;
    }

    function setWorkCompleteCallback(callback as Method?) as Void {
        _workCompleteCallback = callback;
    }

    function setAutoStopCallback(callback as Method?) as Void {
        _autoStopCallback = callback;
    }

    function setCycleCompleteCallback(callback as Method?) as Void {
        _cycleCompleteCallback = callback;
    }

    // ── Mode ──────────────────────────────────────────────────

    function getMode() as TimerMode {
        return _mode;
    }

    function setMode(mode as TimerMode) as Void {
        if (_state != STATE_IDLE) {
            return;  // Cannot switch mode mid-session
        }
        _mode = mode;
        Application.Properties.setValue("timerMode", mode as Number);
        resetToIdle();
    }

    function isFlowtimer() as Boolean {
        return _mode == MODE_FLOWTIMER;
    }

    function isPomodoro() as Boolean {
        return _mode == MODE_POMODORO;
    }

    // ── Start / Pause / Resume ────────────────────────────────

    //! Start the timer (mode-aware)
    function start() as Void {
        if (_state == STATE_IDLE) {
            _activeSeconds = 0;
            _nudgeFired = false;
            if (_mode == MODE_FLOWTIMER) {
                _state = STATE_FLOW_RUNNING;
            } else {
                _remainingSeconds = _workDuration;
                _totalSeconds = _workDuration;
                _state = STATE_POMO_WORK;
            }
            startTimer();
        } else if (_state == STATE_FLOW_PAUSED) {
            // Resume Flowtimer from pause
            _state = STATE_FLOW_RUNNING;
            _pauseStartMoment = null;
            // Timer is already running (kept ticking for pause timeout)
        } else if (_state == STATE_POMO_BREAK_WAIT) {
            _state = STATE_POMO_BREAK;
            startTimer();
        }
    }

    //! Pause (Flowtimer only)
    function pause() as Void {
        if (_state == STATE_FLOW_RUNNING) {
            _state = STATE_FLOW_PAUSED;
            _pauseStartMoment = Time.now();
            // Timer keeps ticking for pause timeout check
        } else if (_state == STATE_POMO_BREAK) {
            _state = STATE_POMO_BREAK_WAIT;
            stopTimer();
        }
    }

    //! Reset to idle state
    function resetToIdle() as Void {
        stopTimer();
        _state = STATE_IDLE;
        _activeSeconds = 0;
        _remainingSeconds = _mode == MODE_POMODORO ? _workDuration : 0;
        _totalSeconds = _mode == MODE_POMODORO ? _workDuration : 0;
        _pauseStartMoment = null;
        _nudgeFired = false;
    }

    //! Reset everything including cycle count
    function resetAll() as Void {
        resetToIdle();
        _cyclePosition = 1;
        _pomodorosCompleted = 0;
    }

    //! Advance to next work session (skip break)
    function skipBreak() as Void {
        if (_state == STATE_POMO_BREAK || _state == STATE_POMO_BREAK_WAIT) {
            stopTimer();
            advanceToNextWork();
        }
    }

    // ── Timer internals ───────────────────────────────────────

    private function startTimer() as Void {
        if (_timer == null) {
            _timer = new Timer.Timer();
        }
        _timer.start(method(:onTick), 1000, true);
    }

    private function stopTimer() as Void {
        if (_timer != null) {
            _timer.stop();
        }
    }

    //! Called every second
    function onTick() as Void {
        if (_state == STATE_FLOW_RUNNING) {
            _activeSeconds++;

            // 90-minute nudge
            if (!_nudgeFired && _activeSeconds >= FLOW_NUDGE_TIME) {
                _nudgeFired = true;
                vibrate();  // Gentle nudge
            }

            // 120-minute hard ceiling
            if (_activeSeconds >= FLOW_CEILING_TIME) {
                stopTimer();
                _state = STATE_IDLE;
                vibrate();
                if (_autoStopCallback != null) {
                    _autoStopCallback.invoke();
                }
                return;
            }

        } else if (_state == STATE_FLOW_PAUSED) {
            // Check 15-minute pause timeout
            if (_pauseStartMoment != null) {
                var elapsed = Time.now().subtract(_pauseStartMoment).value();
                if (elapsed >= FLOW_PAUSE_TIMEOUT) {
                    stopTimer();
                    _state = STATE_IDLE;
                    vibrate();
                    _pauseStartMoment = null;
                    if (_autoStopCallback != null) {
                        _autoStopCallback.invoke();
                    }
                    return;
                }
            }

        } else if (_state == STATE_POMO_WORK) {
            _activeSeconds++;
            _remainingSeconds--;
            if (_remainingSeconds <= 0) {
                onPomoWorkComplete();
                return;
            }

        } else if (_state == STATE_POMO_BREAK) {
            _remainingSeconds--;
            if (_remainingSeconds <= 0) {
                onPomoBreakComplete();
                return;
            }
        }

        if (_tickCallback != null) {
            _tickCallback.invoke();
        }
    }

    //! Pomodoro work phase completed naturally
    private function onPomoWorkComplete() as Void {
        stopTimer();
        vibrate();

        _pomodorosCompleted++;

        // Notify for session summary
        if (_workCompleteCallback != null) {
            _workCompleteCallback.invoke();
        }

        // Set up break
        startBreak();

        if (_tickCallback != null) {
            _tickCallback.invoke();
        }
    }

    //! Set up a break (paused — user presses START to begin)
    private function startBreak() as Void {
        var breakDuration;
        if (_cyclePosition >= SESSIONS_PER_CYCLE) {
            breakDuration = _longBreakDuration;
        } else {
            breakDuration = _shortBreakDuration;
        }
        _remainingSeconds = breakDuration;
        _totalSeconds = breakDuration;
        _state = STATE_POMO_BREAK_WAIT;
    }

    //! Pomodoro break completed
    private function onPomoBreakComplete() as Void {
        stopTimer();
        vibrate();

        if (_cyclePosition >= SESSIONS_PER_CYCLE) {
            // Cycle complete
            _cyclePosition = 1;
            if (_cycleCompleteCallback != null) {
                _cycleCompleteCallback.invoke();
            }
        }

        advanceToNextWork();

        if (_tickCallback != null) {
            _tickCallback.invoke();
        }
    }

    //! Move to next work session in cycle
    private function advanceToNextWork() as Void {
        if (_cyclePosition < SESSIONS_PER_CYCLE) {
            _cyclePosition++;
        } else {
            _cyclePosition = 1;
        }
        _state = STATE_IDLE;
        _activeSeconds = 0;
        _remainingSeconds = _workDuration;
        _totalSeconds = _workDuration;
    }

    //! Vibration alert
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

    // ── Getters ───────────────────────────────────────────────

    function getState() as TimerState {
        return _state;
    }

    function getActiveSeconds() as Number {
        return _activeSeconds;
    }

    function getRemainingSeconds() as Number {
        return _remainingSeconds;
    }

    function getTotalSeconds() as Number {
        return _totalSeconds;
    }

    //! Get display time string (count-up for Flowtimer, countdown for Pomodoro)
    function getDisplayTimeString() as String {
        if (_mode == MODE_FLOWTIMER) {
            return formatTime(_activeSeconds);
        } else {
            return formatTime(_remainingSeconds);
        }
    }

    //! Format seconds as MM:SS or H:MM:SS
    private function formatTime(seconds as Number) as String {
        var h = seconds / 3600;
        var m = (seconds % 3600) / 60;
        var s = seconds % 60;
        if (h > 0) {
            return h.format("%d") + ":" + m.format("%02d") + ":" + s.format("%02d");
        }
        return m.format("%02d") + ":" + s.format("%02d");
    }

    //! Progress percentage (Pomodoro only, 0 for Flowtimer)
    function getProgress() as Number {
        if (_mode == MODE_FLOWTIMER) {
            return 0;
        }
        if (_totalSeconds == 0) {
            return 0;
        }
        if (_state == STATE_POMO_WORK) {
            return ((_totalSeconds - _remainingSeconds) * 100) / _totalSeconds;
        }
        if (_state == STATE_POMO_BREAK || _state == STATE_POMO_BREAK_WAIT) {
            return ((_totalSeconds - _remainingSeconds) * 100) / _totalSeconds;
        }
        return 0;
    }

    //! Is timer actively running?
    function isRunning() as Boolean {
        return _state == STATE_FLOW_RUNNING ||
               _state == STATE_POMO_WORK ||
               _state == STATE_POMO_BREAK;
    }

    //! Is in a work/focus state (running or paused)?
    function isWorkState() as Boolean {
        return _state == STATE_FLOW_RUNNING ||
               _state == STATE_FLOW_PAUSED ||
               _state == STATE_POMO_WORK;
    }

    //! Is in a break state?
    function isBreakState() as Boolean {
        return _state == STATE_POMO_BREAK || _state == STATE_POMO_BREAK_WAIT;
    }

    //! State label for display
    function getStateLabel() as String {
        switch (_state) {
            case STATE_IDLE:
                return "Ready";
            case STATE_FLOW_RUNNING:
                return "Flow";
            case STATE_FLOW_PAUSED:
                return "Paused";
            case STATE_POMO_WORK:
                return "Focus";
            case STATE_POMO_BREAK:
                return "Break";
            case STATE_POMO_BREAK_WAIT:
                return "Break";
            default:
                return "";
        }
    }

    //! Flowtimer session label based on active duration
    function getFlowSessionLabel() as String {
        var mins = _activeSeconds / 60;
        if (mins < 25) {
            return "Short flow";
        } else if (mins < 60) {
            return "Deep flow";
        } else {
            return "Extended flow";
        }
    }

    //! Get label for a given duration in seconds
    function getFlowSessionLabelForDuration(durationSeconds as Number) as String {
        var mins = durationSeconds / 60;
        if (mins < 25) {
            return "Short flow";
        } else if (mins < 60) {
            return "Deep flow";
        } else {
            return "Extended flow";
        }
    }

    //! Seconds remaining before Flowtimer pause auto-ends
    function getPauseRemainingSeconds() as Number {
        if (_state != STATE_FLOW_PAUSED || _pauseStartMoment == null) {
            return 0;
        }
        var elapsed = Time.now().subtract(_pauseStartMoment).value();
        var remaining = FLOW_PAUSE_TIMEOUT - elapsed;
        return remaining > 0 ? remaining : 0;
    }

    //! Pomodoro cycle position (1-4)
    function getCyclePosition() as Number {
        return _cyclePosition;
    }

    //! Total completed pomodoros
    function getPomodorosCompleted() as Number {
        return _pomodorosCompleted;
    }

    //! Is the current break a long break?
    function isLongBreak() as Boolean {
        return _totalSeconds == _longBreakDuration;
    }

    // ── Settings ──────────────────────────────────────────────

    function setWorkDuration(minutes as Number) as Void {
        _workDuration = minutes * 60;
        Application.Properties.setValue("workDuration", _workDuration);
        if (_state == STATE_IDLE && _mode == MODE_POMODORO) {
            _remainingSeconds = _workDuration;
            _totalSeconds = _workDuration;
        }
    }

    function setShortBreakDuration(minutes as Number) as Void {
        _shortBreakDuration = minutes * 60;
        Application.Properties.setValue("shortBreakDuration", _shortBreakDuration);
    }

    function setLongBreakDuration(minutes as Number) as Void {
        _longBreakDuration = minutes * 60;
        Application.Properties.setValue("longBreakDuration", _longBreakDuration);
    }

    function getWorkDurationMinutes() as Number {
        return _workDuration / 60;
    }

    function getShortBreakDurationMinutes() as Number {
        return _shortBreakDuration / 60;
    }

    function getLongBreakDurationMinutes() as Number {
        return _longBreakDuration / 60;
    }
}

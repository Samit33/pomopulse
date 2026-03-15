import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Settings menu with mode selector and conditional Pomodoro settings
class SettingsMenu extends WatchUi.Menu2 {

    function initialize(timerController as TimerController?) {
        Menu2.initialize({:title => "Settings"});

        // Mode selector (always shown)
        var modeLabel = "Flowtimer";
        if (timerController != null && timerController.isPomodoro()) {
            modeLabel = "Pomodoro";
        }
        addItem(new WatchUi.MenuItem("Timer Mode", modeLabel, :timerMode, null));

        // Pomodoro-specific settings (only shown in Pomodoro mode)
        if (timerController != null && timerController.isPomodoro()) {
            addItem(new WatchUi.MenuItem("Work Duration", null, :workDuration, null));
            addItem(new WatchUi.MenuItem("Short Break", null, :shortBreak, null));
            addItem(new WatchUi.MenuItem("Long Break", null, :longBreak, null));
        }

        addItem(new WatchUi.MenuItem("Clear History", null, :clearHistory, null));
    }
}

//! Settings menu delegate
class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _timerController as TimerController?;

    function initialize(timerController as TimerController?) {
        Menu2InputDelegate.initialize();
        _timerController = timerController;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var tc = _timerController;
        var id = item.getId();

        if (id == :timerMode) {
            showModePicker();
        } else if (id == :workDuration && tc != null) {
            showDurationPicker("Work Duration", tc.getWorkDurationMinutes(), :workDuration);
        } else if (id == :shortBreak && tc != null) {
            showDurationPicker("Short Break", tc.getShortBreakDurationMinutes(), :shortBreak);
        } else if (id == :longBreak && tc != null) {
            showDurationPicker("Long Break", tc.getLongBreakDurationMinutes(), :longBreak);
        } else if (id == :clearHistory) {
            showClearHistoryConfirmation();
        }
    }

    private function showModePicker() as Void {
        var menu = new ModePickerMenu(_timerController);
        var delegate = new ModePickerDelegate(_timerController);
        WatchUi.pushView(menu, delegate, WatchUi.SLIDE_LEFT);
    }

    private function showDurationPicker(title as String, currentValue as Number, settingId as Symbol) as Void {
        var menu = new DurationPickerMenu(title, currentValue, settingId);
        var delegate = new DurationPickerDelegate(_timerController, settingId);
        WatchUi.pushView(menu, delegate, WatchUi.SLIDE_LEFT);
    }

    private function showClearHistoryConfirmation() as Void {
        var dialog = new WatchUi.Confirmation("Clear all history?");
        WatchUi.pushView(dialog, new ClearHistoryDelegate(), WatchUi.SLIDE_LEFT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

//! Mode picker sub-menu
class ModePickerMenu extends WatchUi.Menu2 {

    function initialize(timerController as TimerController?) {
        Menu2.initialize({:title => "Timer Mode"});

        var currentMode = MODE_FLOWTIMER;
        if (timerController != null) {
            currentMode = timerController.getMode();
        }

        var flowSub = currentMode == MODE_FLOWTIMER ? "Current" : null;
        var pomoSub = currentMode == MODE_POMODORO ? "Current" : null;

        addItem(new WatchUi.MenuItem("Flowtimer", flowSub, MODE_FLOWTIMER, null));
        addItem(new WatchUi.MenuItem("Pomodoro", pomoSub, MODE_POMODORO, null));
    }
}

//! Mode picker delegate
class ModePickerDelegate extends WatchUi.Menu2InputDelegate {

    private var _timerController as TimerController?;

    function initialize(timerController as TimerController?) {
        Menu2InputDelegate.initialize();
        _timerController = timerController;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var mode = item.getId() as TimerMode;
        if (_timerController != null) {
            _timerController.setMode(mode);
        }
        // Pop mode picker + settings menu (rebuild settings with new mode items)
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

//! Duration picker menu
class DurationPickerMenu extends WatchUi.Menu2 {

    function initialize(title as String, currentValue as Number, settingId as Symbol) {
        Menu2.initialize({:title => title});

        var options;
        if (settingId == :workDuration) {
            options = [15, 20, 25, 30, 35, 40, 45, 50, 55, 60];
        } else if (settingId == :shortBreak) {
            options = [3, 5, 10, 15];
        } else {
            options = [10, 15, 20, 25, 30];
        }

        for (var i = 0; i < options.size(); i++) {
            var minutes = options[i];
            var label = minutes.format("%d") + " min";
            var subLabel = (minutes == currentValue) ? "Current" : null;
            addItem(new WatchUi.MenuItem(label, subLabel, minutes, null));
        }
    }
}

//! Duration picker delegate
class DurationPickerDelegate extends WatchUi.Menu2InputDelegate {

    private var _timerController as TimerController?;
    private var _settingId as Symbol;

    function initialize(timerController as TimerController?, settingId as Symbol) {
        Menu2InputDelegate.initialize();
        _timerController = timerController;
        _settingId = settingId;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var minutes = item.getId() as Number;

        if (_timerController != null) {
            if (_settingId == :workDuration) {
                _timerController.setWorkDuration(minutes);
            } else if (_settingId == :shortBreak) {
                _timerController.setShortBreakDuration(minutes);
            } else if (_settingId == :longBreak) {
                _timerController.setLongBreakDuration(minutes);
            }
        }

        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

//! Clear history confirmation delegate
class ClearHistoryDelegate extends WatchUi.ConfirmationDelegate {

    function initialize() {
        ConfirmationDelegate.initialize();
    }

    function onResponse(response as Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            var historyManager = getApp().getHistoryManager();
            if (historyManager != null) {
                historyManager.clearHistory();
            }
        }
        return true;
    }
}

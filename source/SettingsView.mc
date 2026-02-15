using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;

//! Settings menu using Menu2
class SettingsMenu extends WatchUi.Menu2 {

    //! Constructor
    function initialize() {
        Menu2.initialize({:title => "Settings"});

        // Add menu items
        addItem(new WatchUi.MenuItem("Work Duration", null, :workDuration, null));
        addItem(new WatchUi.MenuItem("Short Break", null, :shortBreak, null));
        addItem(new WatchUi.MenuItem("Long Break", null, :longBreak, null));
        addItem(new WatchUi.MenuItem("Auto-start Break", null, :autoStart, null));
        addItem(new WatchUi.MenuItem("Clear History", null, :clearHistory, null));
    }
}

//! Settings menu delegate
class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _timerController as TimerController?;

    //! Constructor
    function initialize(timerController as TimerController?) {
        Menu2InputDelegate.initialize();
        _timerController = timerController;
    }

    //! Handle menu item selection
    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();

        if (id == :workDuration) {
            showDurationPicker("Work Duration", _timerController.getWorkDurationMinutes(), :workDuration);
        } else if (id == :shortBreak) {
            showDurationPicker("Short Break", _timerController.getShortBreakDurationMinutes(), :shortBreak);
        } else if (id == :longBreak) {
            showDurationPicker("Long Break", _timerController.getLongBreakDurationMinutes(), :longBreak);
        } else if (id == :autoStart) {
            toggleAutoStart();
        } else if (id == :clearHistory) {
            showClearHistoryConfirmation();
        }
    }

    //! Show duration picker menu
    private function showDurationPicker(title as String, currentValue as Number, settingId as Symbol) as Void {
        var menu = new DurationPickerMenu(title, currentValue, settingId);
        var delegate = new DurationPickerDelegate(_timerController, settingId);
        WatchUi.pushView(menu, delegate, WatchUi.SLIDE_LEFT);
    }

    //! Toggle auto-start break setting
    private function toggleAutoStart() as Void {
        if (_timerController != null) {
            var current = _timerController.getAutoStartBreak();
            _timerController.setAutoStartBreak(!current);
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
    }

    //! Show clear history confirmation
    private function showClearHistoryConfirmation() as Void {
        var dialog = new WatchUi.Confirmation("Clear all history?");
        WatchUi.pushView(dialog, new ClearHistoryDelegate(), WatchUi.SLIDE_LEFT);
    }

    //! Handle back button
    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

//! Duration picker menu
class DurationPickerMenu extends WatchUi.Menu2 {

    //! Constructor
    function initialize(title as String, currentValue as Number, settingId as Symbol) {
        Menu2.initialize({:title => title});

        // Duration options (in minutes)
        var options;
        if (settingId == :workDuration) {
            options = [15, 20, 25, 30, 35, 40, 45, 50, 55, 60];
        } else {
            options = [3, 5, 10, 15, 20, 25, 30];
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

    //! Constructor
    function initialize(timerController as TimerController?, settingId as Symbol) {
        Menu2InputDelegate.initialize();
        _timerController = timerController;
        _settingId = settingId;
    }

    //! Handle menu item selection
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

        // Pop back to main view
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    //! Handle back button
    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

//! Clear history confirmation delegate
class ClearHistoryDelegate extends WatchUi.ConfirmationDelegate {

    //! Constructor
    function initialize() {
        ConfirmationDelegate.initialize();
    }

    //! Handle confirmation response
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

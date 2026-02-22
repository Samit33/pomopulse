#!/bin/bash
# PomoPulse UI Screenshot Automation
# Takes screenshots at each button press to visually verify the UI.
#
# Requirements: sudo apt-get install -y xdotool scrot
# Usage: ./ui-test.sh

export PATH="$HOME/jre21/bin:$HOME/connectiq-sdk/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/libs:$LD_LIBRARY_PATH"

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
PRG="$SCRIPT_DIR/bin/PomoPulse.prg"
KEY="$HOME/garmin-keys/developer.der"
SIM_APP="$HOME/.Garmin/ConnectIQ/AppImages/simulator-8.4.1.AppImage"
SHOTS_DIR="$SCRIPT_DIR/screenshots"

# ── preflight checks ─────────────────────────────────────────────────────────
for tool in xdotool monkeyc monkeydo; do
    if ! command -v "$tool" &>/dev/null; then
        echo "ERROR: '$tool' not found."
        [ "$tool" = "xdotool" ] && echo "  Install with: sudo apt-get install -y xdotool"
        exit 1
    fi
done

if [ -z "$DISPLAY" ]; then
    echo "ERROR: No DISPLAY set. Run from a session with X11/WSLg."
    exit 1
fi

mkdir -p "$SHOTS_DIR"
STEP=0
SIM_WID=""

# ── helpers ──────────────────────────────────────────────────────────────────
find_sim_window() {
    # "CIQ Simulator" is the title bar text; search returns child windows too,
    # use the last one which tends to be the parent/main window.
    for pattern in "CIQ Simulator" "Connect IQ" "Garmin" "Simulator"; do
        local wids wid
        wids=$(xdotool search --name "$pattern" 2>/dev/null)
        wid=$(echo "$wids" | tail -1)
        [ -n "$wid" ] && { echo "$wid"; return; }
    done
    echo ""
}

# Re-detect window ID — the simulator creates a child window after app loads.
# Pick the most recently created window matching the simulator.
refresh_window() {
    local new_wid
    new_wid=$(find_sim_window)
    if [ -n "$new_wid" ] && [ "$new_wid" != "$SIM_WID" ]; then
        echo "  [window] updated: $SIM_WID → $new_wid"
        SIM_WID="$new_wid"
    fi
}

screenshot() {
    local label="$1"
    STEP=$((STEP + 1))
    local file
    file=$(printf "%s/%02d_%s.png" "$SHOTS_DIR" "$STEP" "$label")
    sleep 0.8   # let UI settle after any action

    # Raise window in X11 then use PowerShell to pull it to Windows foreground.
    xdotool windowraise "$SIM_WID" 2>/dev/null || true
    xdotool windowfocus --sync "$SIM_WID" 2>/dev/null || true
    sleep 0.3

    # WSLg renders via Windows RDP — X11 tools only see a black framebuffer.
    # Use PowerShell to bring simulator to Windows foreground then screenshot.
    local win_tmp='C:\Users\Public\pomo_ss.png'
    local wsl_tmp
    wsl_tmp=$(wslpath -u "$win_tmp")

    powershell.exe -NoProfile -Command "
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName Microsoft.VisualBasic
        # Bring the CIQ Simulator window to Windows foreground
        try { [Microsoft.VisualBasic.Interaction]::AppActivate('CIQ Simulator') } catch {}
        Start-Sleep -Milliseconds 400
        \$s   = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        \$bmp = New-Object System.Drawing.Bitmap(\$s.Width, \$s.Height)
        \$g   = [System.Drawing.Graphics]::FromImage(\$bmp)
        \$g.CopyFromScreen(0, 0, 0, 0, \$bmp.Size)
        \$bmp.Save('$win_tmp')
        \$g.Dispose(); \$bmp.Dispose()
    " 2>/dev/null

    if cp "$wsl_tmp" "$file" 2>/dev/null; then
        echo "  [shot $STEP] $label → $(basename "$file")"
    else
        echo "  [shot $STEP] WARNING: screenshot failed for $label"
    fi
}

press() {
    local key="$1" label="$2"
    echo "  [press] $label"
    xdotool key --window "$SIM_WID" --clearmodifiers "$key" 2>/dev/null || {
        echo "  [press] window gone — re-detecting..."
        refresh_window
        xdotool key --window "$SIM_WID" --clearmodifiers "$key" 2>/dev/null || true
    }
}

long_press() {
    local key="$1" label="$2" duration="${3:-1.0}"
    echo "  [hold ] $label (${duration}s)"
    xdotool keydown --window "$SIM_WID" --clearmodifiers "$key" 2>/dev/null || true
    sleep "$duration"
    xdotool keyup   --window "$SIM_WID" --clearmodifiers "$key" 2>/dev/null || true
}

wait_for_socket() {
    for i in $(seq 1 20); do
        python3 -c "import socket; s=socket.create_connection(('localhost',1234),0.5); s.close()" 2>/dev/null \
            && { echo "  socket ready (${i}s)"; return 0; }
        sleep 1
        printf "  waiting for simulator... %ds\r" "$i"
    done
    echo "WARNING: simulator socket not detected, continuing anyway."
}

# ── build ─────────────────────────────────────────────────────────────────────
echo "════════════════════════════════════════"
echo " PomoPulse UI Test"
echo "════════════════════════════════════════"
echo
echo "[ BUILD ]"
monkeyc -d fr255 -f "$SCRIPT_DIR/monkey.jungle" -o "$PRG" -y "$KEY" -l 0 || {
    echo "Build failed!"; exit 1
}
echo "  OK — $(du -sh "$PRG" | cut -f1)"

# ── launch simulator ──────────────────────────────────────────────────────────
echo
echo "[ SIMULATOR ]"
pkill -f "simulator-8.4.1" 2>/dev/null && sleep 1

"$SIM_APP" &
SIM_BG_PID=$!
echo "  launched (pid $SIM_BG_PID)"

echo "  waiting for window..."
for i in $(seq 1 25); do
    sleep 1
    SIM_WID=$(find_sim_window)
    [ -n "$SIM_WID" ] && { echo "  window: $SIM_WID (${i}s)"; break; }
done

if [ -z "$SIM_WID" ]; then
    echo "ERROR: Simulator window not found. Is a display available?"
    exit 1
fi

wait_for_socket
sleep 2

# ── push app ──────────────────────────────────────────────────────────────────
echo
echo "[ PUSH APP ]"
monkeydo "$PRG" fr255 &
MONKEY_PID=$!
echo "  waiting for app to load..."
sleep 9

# Re-detect window after app loads (simulator may create a new child window)
refresh_window

# ── screenshot tests ──────────────────────────────────────────────────────────
echo
echo "[ UI TESTS ]"

screenshot "initial_load"

echo
echo "-- START: begin timer --"
press Return "START"
screenshot "timer_started"

echo
echo "-- wait 3s while timer ticks --"
sleep 3
screenshot "timer_ticking"

echo
echo "-- START: pause timer --"
press Return "START_pause"
screenshot "timer_paused"

echo
echo "-- UP: open stats view --"
press Up "UP_stats"
screenshot "stats_view"

echo
echo "-- DOWN: scroll stats (if scrollable) --"
press Down "DOWN_in_stats"
screenshot "stats_scrolled"

echo
echo "-- BACK: return from stats --"
press Escape "BACK_from_stats"
screenshot "back_to_main"

echo
echo "-- DOWN: skip phase (work→break) --"
press Down "DOWN_skip_phase"
screenshot "phase_skipped"

echo
echo "-- UP long press: open settings menu --"
long_press Up "UP_hold_settings" 1.2
screenshot "settings_menu"

echo
echo "-- DOWN: navigate settings --"
press Down "DOWN_settings_nav"
screenshot "settings_nav_1"
press Down "DOWN_settings_nav"
screenshot "settings_nav_2"

echo
echo "-- BACK: exit settings --"
press Escape "BACK_from_settings"
screenshot "back_to_main_final"

# ── cleanup ───────────────────────────────────────────────────────────────────
kill "$MONKEY_PID" 2>/dev/null || true

# ── summary ───────────────────────────────────────────────────────────────────
echo
echo "════════════════════════════════════════"
echo " Done. $STEP screenshots saved to:"
echo "   $SHOTS_DIR/"
echo "════════════════════════════════════════"
ls -1 "$SHOTS_DIR"/*.png

#!/bin/bash
# PomoPulse UI Test Suite
#
# Runs after any UI code change to verify all screens render correctly.
# Produces a timestamped HTML report with screenshots for visual review.
# On first run (or with --save-baseline) screenshots are saved as baselines.
#
# Usage:
#   ./tests/ui-suite.sh                # Run suite, compare to baseline
#   ./tests/ui-suite.sh --save-baseline  # Run suite, update baseline
#   ./tests/ui-suite.sh --report-only    # Open last report without re-running

set -euo pipefail

# ── config ────────────────────────────────────────────────────────────────────
export PATH="$HOME/jre21/bin:$HOME/connectiq-sdk/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

SUITE_DIR="$(dirname "$(realpath "$0")")"
ROOT_DIR="$(dirname "$SUITE_DIR")"
PRG="$ROOT_DIR/bin/PomoPulse.prg"
KEY="$HOME/garmin-keys/developer.der"
SIM_APP="$HOME/.Garmin/ConnectIQ/AppImages/simulator-8.4.1.AppImage"
VALIDATOR="$SUITE_DIR/validate_screen.py"

BASELINE_DIR="$SUITE_DIR/baseline"
RESULTS_DIR="$SUITE_DIR/results/$(date +%Y%m%d_%H%M%S)"
REPORT="$SUITE_DIR/report.html"

# ── watch face crop (fr255-specific) ──────────────────────────────────────────
# Simulator window: 446x700. Display circle center: (170,255), radius: 130.
# Crop = square bounding box with 2px margin → (38,123,264,264).
WATCH_CROP_X=38
WATCH_CROP_Y=123
WATCH_CROP_W=264
WATCH_CROP_H=264

SAVE_BASELINE=false
REPORT_ONLY=false
for arg in "$@"; do
    [ "$arg" = "--save-baseline" ] && SAVE_BASELINE=true
    [ "$arg" = "--report-only"   ] && REPORT_ONLY=true
done

# ── state tracking ────────────────────────────────────────────────────────────
SIM_WID=""
MONKEY_PID=""
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
declare -a TEST_NAMES=()
declare -a TEST_STATUS=()
declare -a TEST_SCREENSHOTS=()
declare -a TEST_BASELINES=()
declare -a TEST_NOTES=()

# ── helpers ───────────────────────────────────────────────────────────────────
log()  { echo "  $*"; }
step() { echo; echo "── $*"; }
ok()   { echo "  [OK] $*"; }
warn() { echo "  [!]  $*"; }
err()  { echo "  [ERR] $*"; }

find_sim_window() {
    for pattern in "CIQ Simulator" "Connect IQ" "Garmin" "Simulator"; do
        local wid
        wid=$(xdotool search --name "$pattern" 2>/dev/null | tail -1)
        [ -n "$wid" ] && { echo "$wid"; return; }
    done
    echo ""
}

refresh_window() {
    local new
    new=$(find_sim_window)
    if [ -n "$new" ] && [ "$new" != "$SIM_WID" ]; then
        log "window updated: $SIM_WID → $new"
        SIM_WID="$new"
    fi
}

# Map shell key names to "VK_CODE KEYDOWN_LPARAM KEYUP_LPARAM".
# Arrow keys are extended keys (bit 24 in lParam) — without this the WSLg
# RDP bridge cannot correctly translate them to Linux/Wayland key events.
# lParam bits: 0-15 repeat(1), 16-23 scan code, 24 extended, 30-31 transition.
_vk() {
    case "$1" in
        Return)  echo "0x0D 0x001C0001 0xC01C0001" ;;  # VK_RETURN, scan=0x1C
        Escape)  echo "0x1B 0x00010001 0xC0010001" ;;  # VK_ESCAPE, scan=0x01
        Up)      echo "0x26 0x01480001 0xC1480001" ;;  # VK_UP,     scan=0x48, extended
        Down)    echo "0x28 0x01500001 0xC1500001" ;;  # VK_DOWN,   scan=0x50, extended
        *)       echo "";;
    esac
}

# Win32 PostMessage key injection.
# PostMessage delivers WM_KEYDOWN directly to the simulator's Win32 message queue,
# bypassing Wayland/X11 focus entirely (XTEST fails because Weston WM does not
# honour XSetInputFocus or _NET_ACTIVE_WINDOW from a background bash process).
# NOTE: SetForegroundWindow is intentionally NOT called here — it causes the Garmin
# CIQ runtime to receive spurious WM_ACTIVATE / FocusIn events that the CIQ
# BehaviorDelegate registers as phantom button presses, corrupting navigation state.
# Instead, setup_simulator runs enough screenshot warm-up cycles (each of which
# calls BringWindowToTop) so that Windows grants persistent foreground permission
# to the simulator before the first test key press is sent.
_win32_key() {
    local vk="$1" lpdn="$2" lpup="$3" duration_ms="${4:-80}"
    powershell.exe -NoProfile -Command "
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class K {
    public delegate bool EWP(IntPtr h, IntPtr l);
    [DllImport(\"user32.dll\")] public static extern bool EnumWindows(EWP p, IntPtr l);
    [DllImport(\"user32.dll\")] public static extern int  GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport(\"user32.dll\")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport(\"user32.dll\")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    public static IntPtr Find(string t) {
        IntPtr f=IntPtr.Zero;
        EnumWindows((h,l)=>{ var s=new StringBuilder(256); GetWindowText(h,s,256);
            if(s.ToString().Contains(t)&&IsWindowVisible(h)){f=h;return false;} return true; },IntPtr.Zero);
        return f; }
}
'@
\$h = [K]::Find('CIQ Simulator')
if (\$h -ne [IntPtr]::Zero) {
    [void][K]::PostMessage(\$h, 0x0100, [IntPtr]$vk, [IntPtr]$lpdn)  # WM_KEYDOWN
    Start-Sleep -Milliseconds $duration_ms
    [void][K]::PostMessage(\$h, 0x0101, [IntPtr]$vk, [IntPtr]$lpup)  # WM_KEYUP
}
    " 2>/dev/null || true
}

_press() {
    local key="$1"
    local vklp; vklp=$(_vk "$key")
    [ -z "$vklp" ] && { warn "unknown key: $key"; return; }
    local vk lpdn lpup
    vk=$(echo "$vklp" | cut -d' ' -f1)
    lpdn=$(echo "$vklp" | cut -d' ' -f2)
    lpup=$(echo "$vklp" | cut -d' ' -f3)
    _win32_key "$vk" "$lpdn" "$lpup" 80
    sleep 0.3  # let the app process the key event
}

_hold() {
    local key="$1" duration="${2:-1.2}"
    local vklp; vklp=$(_vk "$key")
    [ -z "$vklp" ] && { warn "unknown key: $key"; return; }
    local vk lpdn lpup ms
    vk=$(echo "$vklp" | cut -d' ' -f1)
    lpdn=$(echo "$vklp" | cut -d' ' -f2)
    lpup=$(echo "$vklp" | cut -d' ' -f3)
    ms=$(python3 -c "print(int($duration * 1000))")
    _win32_key "$vk" "$lpdn" "$lpup" "$ms"
    sleep 0.3
}

_screenshot() {
    local path="$1"

    # Get simulator window screen position via xdotool (reliable in WSLg)
    local geo wx wy ww wh
    geo=$(xdotool getwindowgeometry --shell "$SIM_WID" 2>/dev/null) || geo=""
    wx=$(echo "$geo" | grep '^X='      | cut -d= -f2 || echo "")
    wy=$(echo "$geo" | grep '^Y='      | cut -d= -f2 || echo "")
    ww=$(echo "$geo" | grep '^WIDTH='  | cut -d= -f2 || echo "")
    wh=$(echo "$geo" | grep '^HEIGHT=' | cut -d= -f2 || echo "")

    local win_tmp='C:\Users\Public\pomo_ss_suite.png'
    local wsl_tmp
    wsl_tmp=$(wslpath -u "$win_tmp")

    # Simulator was set TOPMOST at setup time — CopyFromScreen can capture it directly
    # at its window coordinates without BringWindowToTop.  Avoiding BringWindowToTop /
    # SetForegroundWindow here is critical: those calls generate Win32 WM_ACTIVATE events
    # that the Garmin CIQ runtime registers as spurious button presses, corrupting state.
    powershell.exe -NoProfile -Command "
Add-Type -AssemblyName System.Drawing
Start-Sleep -Milliseconds 400
\$full = New-Object System.Drawing.Bitmap($ww, $wh)
\$g    = [System.Drawing.Graphics]::FromImage(\$full)
\$g.CopyFromScreen($wx, $wy, 0, 0, \$full.Size)
\$g.Dispose()
\$rect = New-Object System.Drawing.Rectangle($WATCH_CROP_X, $WATCH_CROP_Y, $WATCH_CROP_W, $WATCH_CROP_H)
\$crop = \$full.Clone(\$rect, \$full.PixelFormat)
\$crop.Save('$win_tmp')
\$full.Dispose(); \$crop.Dispose()
    " 2>/dev/null || true
    cp "$wsl_tmp" "$path" 2>/dev/null || true
    sleep 0.3
}

# Run validate_screen.py and return "OK" or "FAIL: <reason>"
_validate() {
    local cmd="$1" path="$2" extra="${3:-}"
    [ ! -f "$path" ] && { echo "FAIL: screenshot missing"; return 0; }

    local out rc=0
    if [ "$cmd" = "scroll" ] && [ -n "$extra" ]; then
        out=$(python3 "$VALIDATOR" scroll "$extra" "$path" 2>/dev/null) && rc=0 || rc=$?
    else
        out=$(python3 "$VALIDATOR" "$cmd" "$path" 2>/dev/null) && rc=0 || rc=$?
    fi

    if [ "$rc" -eq 0 ]; then
        echo "OK"
    else
        local reason
        reason=$(echo "$out" | python3 -c \
            "import sys,json; d=json.load(sys.stdin); print(d.get('reason','unknown'))" 2>/dev/null \
            || echo "check failed")
        echo "FAIL: $reason"
    fi
    return 0
}

# Pixel-level diff against baseline (uses validate_screen.py scroll check as a diff tool).
_diff_baseline() {
    local current="$1" baseline="$2"
    [ ! -f "$baseline" ] && { echo "NEW"; return 0; }
    local out rc=0
    out=$(python3 "$VALIDATOR" scroll "$baseline" "$current" 2>/dev/null) && rc=0 || rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "CHANGED"   # differ from baseline
    else
        echo "MATCH"     # identical to baseline
    fi
    return 0
}

# ── test runner ───────────────────────────────────────────────────────────────
# run_test <name> <slug> <nav_fn> <note> [scroll_ref_slug]
#   scroll_ref_slug: slug of a previous test to diff against (for scroll checks)
run_test() {
    local name="$1" slug="$2" nav_fn="$3" note="${4:-}" scroll_ref="${5:-}"
    local shot="$RESULTS_DIR/${slug}.png"
    local base="$BASELINE_DIR/${slug}.png"

    echo
    printf "  TEST: %-40s" "$name"

    # Navigate then screenshot
    sleep 0.6
    "$nav_fn"
    sleep 0.8
    _screenshot "$shot"

    local status="PASS"
    local reasons=()
    local diff="N/A"

    # 1. Content check — is the watch face rendering anything?
    local cv; cv=$(_validate content "$shot")
    if [[ "$cv" != "OK" ]]; then
        status="FAIL"; reasons+=("$cv")
    fi

    # 2. Overflow check — does content stay inside the circular boundary?
    if [[ "$status" == "PASS" ]]; then
        local ov; ov=$(_validate overflow "$shot")
        if [[ "$ov" != "OK" ]]; then
            status="OVERFLOW"; reasons+=("$ov")
        fi
    fi

    # 3. Scroll check — did the content change vs a reference screenshot?
    if [[ "$status" == "PASS" && -n "$scroll_ref" ]]; then
        local ref_shot="$RESULTS_DIR/${scroll_ref}.png"
        local sv; sv=$(_validate scroll "$shot" "$ref_shot")
        if [[ "$sv" != "OK" ]]; then
            status="FAIL"; reasons+=("$sv")
        fi
    fi

    # 4. Baseline diff (informational; skipped in --save-baseline mode)
    if [[ "$status" == "PASS" ]] && ! $SAVE_BASELINE; then
        diff=$(_diff_baseline "$shot" "$base")
        if [[ "$diff" == "CHANGED" ]]; then
            status="CHANGED"
            reasons+=("FAIL: Differs from baseline — re-run with --save-baseline if intentional")
        fi
    fi

    # Save baseline if requested or no baseline exists yet
    if $SAVE_BASELINE || [ ! -f "$base" ]; then
        cp "$shot" "$base" 2>/dev/null && diff="BASELINE"
    fi

    local reason="${reasons[*]:-}"
    TEST_NAMES+=("$name")
    TEST_STATUS+=("$status")
    TEST_SCREENSHOTS+=("$shot")
    TEST_BASELINES+=("$base")
    TEST_NOTES+=("$reason | diff=$diff | $note")

    case "$status" in
        PASS)     echo "PASS";                         PASS_COUNT=$((PASS_COUNT+1)) ;;
        CHANGED)  echo "CHANGED (review baseline)";    FAIL_COUNT=$((FAIL_COUNT+1)) ;;
        OVERFLOW) echo "OVERFLOW (${reasons[*]:-})";   FAIL_COUNT=$((FAIL_COUNT+1)) ;;
        *)        echo "FAIL (${reasons[*]:-})";       FAIL_COUNT=$((FAIL_COUNT+1)) ;;
    esac
}

# ── navigation functions ───────────────────────────────────────────────────────
# Each nav_* function brings the UI to the target state.
# Called right before the screenshot is taken.
# The app starts in STATE_IDLE after load.

_NAV_STATE="idle"  # tracks current logical state

_to_idle() {
    # From any state: press BACK to exit stats/menus/running → idle
    # Safe to call multiple times (if already idle, does nothing extra)
    case "$_NAV_STATE" in
        stats|settings)
            _press Escape; sleep 0.3 ;;  # exit view/menu → back to main
    esac
    case "$_NAV_STATE" in
        running|paused|break)
            _press Escape; sleep 0.3 ;;  # BACK resets timer → idle
    esac
    _NAV_STATE="idle"
}

nav_idle() {
    : # already in idle after app load; nothing to do
}

nav_timer_running() {
    _to_idle
    _press Return     # START → running
    sleep 1
    _NAV_STATE="running"
}

nav_timer_ticking() {
    # Called 3s after nav_timer_running (state stays running)
    sleep 3
}

nav_timer_paused() {
    _press Return     # START → pause (must be in running state)
    _NAV_STATE="paused"
}

nav_short_break() {
    _to_idle
    _press Down       # DOWN from idle → skip to short break
    sleep 0.3
    _NAV_STATE="break"
}

nav_stats_view() {
    _to_idle
    _press Up         # UP → stats view
    _NAV_STATE="stats"
}

nav_stats_scroll() {
    _press Down       # DOWN in stats → scroll (stays in stats)
}

nav_back_from_stats() {
    _press Escape     # BACK → return to main
    _NAV_STATE="idle"
}

nav_break_hint() {
    : # already on break screen — re-screenshot to verify hint text
}

# ── simulator setup ───────────────────────────────────────────────────────────
setup_simulator() {
    step "BUILD"
    monkeyc -d fr255 -f "$ROOT_DIR/monkey.jungle" -o "$PRG" -y "$KEY" -l 0 || {
        err "Build failed — aborting."; exit 1
    }
    log "OK — $(du -sh "$PRG" | cut -f1)"

    step "SIMULATOR"
    pkill -f "simulator-8.4.1" 2>/dev/null && sleep 1 || true

    "$SIM_APP" &
    log "launched (pid $!)"

    log "waiting for window..."
    for i in $(seq 1 25); do
        sleep 1
        SIM_WID=$(find_sim_window)
        [ -n "$SIM_WID" ] && { log "window: $SIM_WID (${i}s)"; break; }
    done

    [ -z "$SIM_WID" ] && { err "Simulator window not found."; exit 1; }

    # Wait for socket
    for i in $(seq 1 20); do
        python3 -c "import socket; s=socket.create_connection(('localhost',1234),0.5); s.close()" 2>/dev/null \
            && { log "socket ready (${i}s)"; break; }
        sleep 1
    done
    sleep 2

    step "PUSH APP"
    monkeydo "$PRG" fr255 &
    MONKEY_PID=$!
    log "waiting for app to load..."
    # CIQ runtime needs ~20s to fully initialize its input handling.
    # With < 20s, the first few key injections are silently dropped.
    sleep 20
    refresh_window

    # Make the simulator window TOPMOST (always-on-top) once.
    # This lets _screenshot use a simple CopyFromScreen without BringWindowToTop.
    # Avoiding BringWindowToTop/SetForegroundWindow in every screenshot is critical:
    # those calls generate WM_ACTIVATE events that the Garmin CIQ runtime registers
    # as spurious button presses, corrupting navigation state.
    log "setting simulator TOPMOST..."
    powershell.exe -NoProfile -Command "
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class T {
    public delegate bool EWP(IntPtr h, IntPtr l);
    [DllImport(\"user32.dll\")] public static extern bool EnumWindows(EWP p, IntPtr l);
    [DllImport(\"user32.dll\")] public static extern int  GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport(\"user32.dll\")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport(\"user32.dll\")] public static extern bool SetWindowPos(IntPtr h, IntPtr insertAfter, int x, int y, int cx, int cy, uint flags);
    public static IntPtr Find(string t) {
        IntPtr f=IntPtr.Zero;
        EnumWindows((h,l)=>{ var s=new StringBuilder(256); GetWindowText(h,s,256);
            if(s.ToString().Contains(t)&&IsWindowVisible(h)){f=h;return false;} return true; },IntPtr.Zero);
        return f; }
}
'@
\$h = [T]::Find('CIQ Simulator')
if (\$h -ne [IntPtr]::Zero) {
    # HWND_TOPMOST = -1; SWP_NOMOVE | SWP_NOSIZE = 0x0003
    [void][T]::SetWindowPos(\$h, [IntPtr](-1), 0, 0, 0, 0, 0x0003)
    Write-Host 'TOPMOST set'
}
    " 2>/dev/null || true

    # Single warm-up screenshot to verify the pipeline works.
    log "priming screenshot pipeline..."
    _screenshot /tmp/pomo_warmup.png 2>/dev/null || true
    rm -f /tmp/pomo_warmup.png 2>/dev/null || true
    sleep 0.5
}

teardown_simulator() {
    kill "$MONKEY_PID" 2>/dev/null || true
    pkill -f "simulator-8.4.1" 2>/dev/null || true
}

# ── HTML report ───────────────────────────────────────────────────────────────
generate_report() {
    local ts
    ts=$(date "+%Y-%m-%d %H:%M:%S")
    local total=$(( PASS_COUNT + FAIL_COUNT + SKIP_COUNT ))

    cat > "$REPORT" <<HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>PomoPulse UI Test Report</title>
<style>
  body { font-family: system-ui, sans-serif; background:#111; color:#eee; margin:0; padding:20px; }
  h1 { color:#4af; margin-bottom:4px; }
  .meta { color:#888; font-size:13px; margin-bottom:24px; }
  .summary { display:flex; gap:16px; margin-bottom:28px; }
  .badge { padding:8px 18px; border-radius:8px; font-weight:bold; font-size:15px; }
  .badge.pass    { background:#1a4a1a; color:#4f4; }
  .badge.fail    { background:#4a1a1a; color:#f44; }
  .badge.total   { background:#1a2a4a; color:#4af; }
  table { width:100%; border-collapse:collapse; }
  th { background:#1a2a3a; padding:10px 14px; text-align:left; font-size:13px; color:#89b; }
  td { padding:10px 14px; border-bottom:1px solid #222; vertical-align:top; font-size:13px; }
  tr:hover td { background:#1a1a2a; }
  .status { font-weight:bold; padding:3px 10px; border-radius:4px; white-space:nowrap; }
  .PASS    { background:#1a3a1a; color:#4f4; }
  .FAIL    { background:#3a1a1a; color:#f44; }
  .CHANGED { background:#3a2a0a; color:#fa4; }
  .imgs { display:flex; gap:8px; flex-wrap:wrap; }
  .imgs a img { max-width:380px; border:2px solid #333; border-radius:6px;
                cursor:zoom-in; transition:border-color .2s; }
  .imgs a img:hover { border-color:#4af; }
  .label { font-size:11px; color:#888; margin-bottom:2px; }
  .note { font-size:11px; color:#666; margin-top:4px; font-style:italic; }
  .new-badge { font-size:10px; background:#1a2a4a; color:#4af; padding:2px 6px;
               border-radius:3px; vertical-align:middle; margin-left:4px; }
</style>
</head>
<body>
<h1>PomoPulse UI Test Report</h1>
<div class="meta">Generated: $ts &nbsp;|&nbsp; Branch: $(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown") &nbsp;|&nbsp; Commit: $(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")</div>
<div class="summary">
  <div class="badge total">Total: $total</div>
  <div class="badge pass">Pass: $PASS_COUNT</div>
  <div class="badge fail">Fail / Changed: $FAIL_COUNT</div>
</div>
<table>
<tr><th>#</th><th>Test</th><th>Status</th><th>Screenshots</th><th>Notes</th></tr>
HTMLEOF

    for i in "${!TEST_NAMES[@]}"; do
        local name="${TEST_NAMES[$i]}"
        local status="${TEST_STATUS[$i]}"
        local shot="${TEST_SCREENSHOTS[$i]}"
        local base="${TEST_BASELINES[$i]}"
        local note="${TEST_NOTES[$i]}"

        # Make paths relative to the report file location
        local shot_rel base_rel
        shot_rel=$(realpath --relative-to="$SUITE_DIR" "$shot" 2>/dev/null || echo "$shot")
        base_rel=$(realpath --relative-to="$SUITE_DIR" "$base" 2>/dev/null || echo "$base")

        local has_base="false"
        [ -f "$base" ] && has_base="true"

        cat >> "$REPORT" <<ROWEOF
<tr>
  <td>$((i+1))</td>
  <td><strong>$name</strong></td>
  <td><span class="status $status">$status</span></td>
  <td>
    <div class="imgs">
      <div>
        <div class="label">Current</div>
        <a href="$shot_rel" target="_blank"><img src="$shot_rel" alt="current" onerror="this.style.display='none'"></a>
      </div>
ROWEOF
        if $has_base; then
            cat >> "$REPORT" <<BASEEOF
      <div>
        <div class="label">Baseline</div>
        <a href="$base_rel" target="_blank"><img src="$base_rel" alt="baseline" onerror="this.style.display='none'"></a>
      </div>
BASEEOF
        else
            echo "      <div><div class=\"label\">Baseline <span class=\"new-badge\">NEW</span></div><em style=\"color:#555\">No baseline yet</em></div>" >> "$REPORT"
        fi
        cat >> "$REPORT" <<ENDROWEOF
    </div>
    <div class="note">$note</div>
  </td>
  <td></td>
</tr>
ENDROWEOF
    done

    cat >> "$REPORT" <<FOOTEOF
</table>
</body>
</html>
FOOTEOF

    log "Report: $REPORT"
}

# ── main ──────────────────────────────────────────────────────────────────────
if $REPORT_ONLY; then
    [ -f "$REPORT" ] && xdg-open "$REPORT" 2>/dev/null || echo "No report at $REPORT"
    exit 0
fi

mkdir -p "$RESULTS_DIR"

echo
echo "══════════════════════════════════════════════"
echo "  PomoPulse UI Test Suite"
$SAVE_BASELINE && echo "  Mode: SAVE BASELINE" || echo "  Mode: COMPARE"
echo "══════════════════════════════════════════════"

setup_simulator

# ── test cases ────────────────────────────────────────────────────────────────
echo
echo "[ RUNNING TESTS ]"

# TC001 — Main screen: idle state
run_test "Main screen: idle (25:00 Ready)" \
         "TC001_idle_screen" \
         "nav_idle" \
         "Timer at 25:00, Ready label, bpm at bottom"

# TC002 — Main screen: timer starts (Calibrating warmup shown)
run_test "Main screen: timer running (warmup)" \
         "TC002_timer_running" \
         "nav_timer_running" \
         "Countdown visible, Calibrating... warmup indicator"

# TC003 — Main screen: timer ticking (countdown after 3s)
run_test "Main screen: timer ticking (3s elapsed)" \
         "TC003_timer_ticking" \
         "nav_timer_ticking" \
         "Timer counts down from 25:00"

# TC004 — Main screen: paused state
run_test "Main screen: timer paused" \
         "TC004_timer_paused" \
         "nav_timer_paused" \
         "Paused state, gray arc, Paused label"

# TC005 — Break screen: short break label
run_test "Break screen: Short Break label" \
         "TC005_short_break" \
         "nav_short_break" \
         "Should show 'Short Break' in teal (not just 'Break')"

# TC006 — Break screen: pomodoro hint when no flow data (same screen as TC005)
run_test "Break screen: pomodoro hint (no flow data)" \
         "TC006_break_hint" \
         "nav_break_hint" \
         "Should show '#1 done - Rest up!' below Short Break label"

# TC007 — Stats view
run_test "Stats view: Focus Stats screen" \
         "TC007_stats_view" \
         "nav_stats_view" \
         "Should show Today + All Time sections with correct layout"

# TC008 — Stats: DOWN press stability (scroll content requires 5+ completed sessions)
# Full scroll verification (pixel diff vs TC007) can only work after 5 real sessions
# are recorded via natural timer completion, not available on a fresh simulator.
run_test "Stats view: DOWN press (stability check)" \
         "TC008_stats_scrolled" \
         "nav_stats_scroll" \
         "DOWN in stats must not crash the view (scroll requires 5+ real sessions)"

# TC009 — Back navigation from stats
run_test "Navigation: BACK from stats → main screen" \
         "TC009_back_from_stats" \
         "nav_back_from_stats" \
         "Should return to idle main screen"

# ── cleanup + report ──────────────────────────────────────────────────────────
teardown_simulator

echo
echo "[ GENERATING REPORT ]"
generate_report

echo
echo "══════════════════════════════════════════════"
echo "  Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "  Report:  $REPORT"
echo "  Shots:   $RESULTS_DIR/"
echo "══════════════════════════════════════════════"

# Open report in browser
xdg-open "$REPORT" 2>/dev/null || true

# Exit non-zero if any failures
[ "$FAIL_COUNT" -eq 0 ]

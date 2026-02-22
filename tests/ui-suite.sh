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
export LD_LIBRARY_PATH="$HOME/libs:$LD_LIBRARY_PATH"

SUITE_DIR="$(dirname "$(realpath "$0")")"
ROOT_DIR="$(dirname "$SUITE_DIR")"
PRG="$ROOT_DIR/bin/PomoPulse.prg"
KEY="$HOME/garmin-keys/developer.der"
SIM_APP="$HOME/.Garmin/ConnectIQ/AppImages/simulator-8.4.1.AppImage"

BASELINE_DIR="$SUITE_DIR/baseline"
RESULTS_DIR="$SUITE_DIR/results/$(date +%Y%m%d_%H%M%S)"
REPORT="$SUITE_DIR/report.html"

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

_press() {
    local key="$1"
    xdotool key --window "$SIM_WID" --clearmodifiers "$key" 2>/dev/null || {
        refresh_window
        xdotool key --window "$SIM_WID" --clearmodifiers "$key" 2>/dev/null || true
    }
}

_hold() {
    local key="$1" duration="${2:-1.2}"
    xdotool keydown --window "$SIM_WID" --clearmodifiers "$key" 2>/dev/null || true
    sleep "$duration"
    xdotool keyup   --window "$SIM_WID" --clearmodifiers "$key" 2>/dev/null || true
}

_screenshot() {
    local path="$1"
    xdotool windowraise "$SIM_WID" 2>/dev/null || true
    xdotool windowfocus --sync "$SIM_WID" 2>/dev/null || true
    sleep 0.3
    local win_tmp='C:\Users\Public\pomo_ss_suite.png'
    local wsl_tmp
    wsl_tmp=$(wslpath -u "$win_tmp")
    powershell.exe -NoProfile -Command "
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName Microsoft.VisualBasic
        try { [Microsoft.VisualBasic.Interaction]::AppActivate('CIQ Simulator') } catch {}
        Start-Sleep -Milliseconds 400
        \$s   = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        \$bmp = New-Object System.Drawing.Bitmap(\$s.Width, \$s.Height)
        \$g   = [System.Drawing.Graphics]::FromImage(\$bmp)
        \$g.CopyFromScreen(0, 0, 0, 0, \$bmp.Size)
        \$bmp.Save('$win_tmp')
        \$g.Dispose(); \$bmp.Dispose()
    " 2>/dev/null
    cp "$wsl_tmp" "$path" 2>/dev/null || true
}

# Check if screenshot has visible content (not all-black / not missing).
# A real screenshot of the watch face will be >> 100 KB.
# A black or missing screenshot is very small.
_check_content() {
    local f="$1"
    [ ! -f "$f" ] && { echo "MISSING"; return; }
    local size
    size=$(stat -c %s "$f" 2>/dev/null || echo 0)
    [ "$size" -gt 80000 ] && echo "OK" || echo "BLACK"
}

# Pixel-level diff against baseline using Python (optional; skipped if no baseline).
_diff_baseline() {
    local current="$1" baseline="$2"
    [ ! -f "$baseline" ] && { echo "NEW"; return; }
    python3 - "$current" "$baseline" <<'PYEOF'
import sys
def avg_diff(a, b):
    try:
        with open(a,'rb') as fa, open(b,'rb') as fb:
            # Read PNG IDAT chunks as raw bytes and compare sizes as a proxy.
            # A proper diff needs PIL; this is a lightweight heuristic.
            sa, sb = len(fa.read()), len(fb.read())
            ratio = abs(sa - sb) / max(sa, sb, 1)
            if ratio > 0.15:
                print("CHANGED")
            else:
                print("MATCH")
    except Exception:
        print("ERROR")
avg_diff(sys.argv[1], sys.argv[2])
PYEOF
}

# ── test runner ───────────────────────────────────────────────────────────────
# run_test <name> <slug> <nav_cmds_function> <note>
run_test() {
    local name="$1" slug="$2" nav_fn="$3" note="${4:-}"
    local shot="$RESULTS_DIR/${slug}.png"
    local base="$BASELINE_DIR/${slug}.png"

    echo
    printf "  TEST: %-40s" "$name"

    # Run navigation, take screenshot
    sleep 0.6
    "$nav_fn"
    sleep 0.8
    _screenshot "$shot"

    # Validate content
    local content
    content=$(_check_content "$shot")
    local diff="N/A"
    local status="PASS"
    local reason=""

    if [ "$content" != "OK" ]; then
        status="FAIL"
        reason="Screenshot is $content"
    else
        diff=$(_diff_baseline "$shot" "$base")
        if [ "$diff" = "CHANGED" ]; then
            status="CHANGED"
            reason="Differs from baseline"
        fi
    fi

    # Save baseline if requested or if no baseline exists
    if $SAVE_BASELINE || [ ! -f "$base" ]; then
        [ "$content" = "OK" ] && cp "$shot" "$base" && diff="BASELINE"
    fi

    # Record result
    TEST_NAMES+=("$name")
    TEST_STATUS+=("$status")
    TEST_SCREENSHOTS+=("$shot")
    TEST_BASELINES+=("$base")
    TEST_NOTES+=("$reason | diff=$diff | $note")

    case "$status" in
        PASS)    echo "PASS"; PASS_COUNT=$((PASS_COUNT+1)) ;;
        CHANGED) echo "CHANGED (visual diff detected)"; FAIL_COUNT=$((FAIL_COUNT+1)) ;;
        *)       echo "FAIL ($reason)"; FAIL_COUNT=$((FAIL_COUNT+1)) ;;
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
    pkill -f "simulator-8.4.1" 2>/dev/null && sleep 1

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
    sleep 9
    refresh_window
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

# TC008 — Stats scroll
run_test "Stats view: scroll down" \
         "TC008_stats_scrolled" \
         "nav_stats_scroll" \
         "DOWN button should scroll stats (if multiple sessions)"

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

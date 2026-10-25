#!/bin/sh
# Usage: measure_scenarios.sh <app path> <label>
# Quits the running Intermezzo, starts <app path>, and measures CPU per scenario (idle, Settings panes,
# menu-bar panel, a 2-minute idle at 1 s resolution). Needs the debug link intermezzo://debug/settings-close.
# Leaves the measured build running: reopen your usual copy afterwards.
APP="$1"; LABEL="$2"
osascript -e 'tell application id "com.automit.Intermezzo" to quit' >/dev/null 2>&1; sleep 3
open -n "$APP"; sleep 12
P=$(pgrep -f "$APP/Contents/MacOS/Intermezzo" | head -1)
measure() {
  top -l 7 -s 5 -pid $P -stats pid,cpu,idlew 2>/dev/null | awk -v p=$P '$1==p {n++; if (n>1) {c+=$2; w+=$3; k++}} END {printf "%-28s cpu %.2f%%  wakeups/s %.1f\n", "'"$1"'", c/k, w/k/5}'
}
u() { open -a "$APP" "intermezzo://$1"; sleep 2; }
echo "== $LABEL (pid $P)"
u debug/settings-close; u panel-close; measure "idle, nothing open"
u settings/status; measure "Settings: Status"
u settings/light; measure "Settings: Light"
u settings/statistics; measure "Settings: Statistics"
u debug/settings-close; u panel; measure "menu-bar panel open"
u panel-close; measure "idle again"
u debug/settings-close
P=$(pgrep -f "$APP/Contents/MacOS/Intermezzo" | head -1)
top -l 121 -s 1 -pid $P -stats pid,cpu 2>/dev/null | awk -v p=$P '$1==p {n++; if(n>1){v=$2; s+=v; c++; if(v>m)m=v}} END {printf "%-28s cpu %.2f%%  (max %.1f%% in any second)\n", "idle, 2 min, 1 s steps", s/c, m}'
ps -o time= -p $P | awk '{print "process CPU time so far: "$1}'

T=/private/tmp/claude-501/-Users-ramith-code-sound-engineering/737ceb91-aaa1-4ae6-bf56-9f296592de83/scratchpad/uitools; P=31105; L=$T/e-app.log
gf(){ osascript -e 'tell application id "com.adaptivesound.app.test-library" to activate' >/dev/null 2>&1; sleep 0.35; [ "$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true')" = "ASTestLibrary" ] || { echo "ABORT: not frontmost"; return 1; }; }
logsince(){ tail -n +$(( $1 + 1 )) $L | grep "\[UX\]" | sed 's/.*\[UX\] //'; }
ctr(){ $T/ax $P dump 12 | grep -F "$1" | head -1 | sed -E 's/.*\((-?[0-9]+),(-?[0-9]+) ([0-9]+)x([0-9]+)\)$/\1 \2 \3 \4/' | awk '{printf "%d %d", $1+$3/2, $2+$4/2}'; }
menuat(){ $T/ax $P menus | grep "^$1 " | head -1 | sed -E 's/.*\((-?[0-9]+),(-?[0-9]+) ([0-9]+)x([0-9]+)\)$/\1 \2 \3 \4/' | awk '{printf "%d %d", $1+$3/2, $2+$4/2}'; }
selrows(){ $T/ax $P dump 12 | grep "SELECTED" | grep "AXButton d=\"" | grep -v 'd="Songs"\|d="Library"\|d="Albums"\|d="Artists"\|d="Genres"\|d="EQ"\|d="Now Playing"' | sed -E 's/^ *AXButton d="([^,"]{1,26}).*/\1/' | tr '\n' '|'; }

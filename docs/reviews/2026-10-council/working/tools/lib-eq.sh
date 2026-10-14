T=/private/tmp/claude-501/-Users-ramith-code-sound-engineering/737ceb91-aaa1-4ae6-bf56-9f296592de83/scratchpad/uitools; P=53641; L=$T/eq-app.log
front(){ osascript -e 'tell application "System Events" to set frontmost of process "ASTestLibrary" to true' >/dev/null; sleep 0.3; }
sel(){ $T/ax $P dump 9 | grep "SELECTED" | grep -v 'd="Songs"\|d="Library"\|Up Next\|Now Playing"\|d="Albums"\|d="Artists"\|d="Genres"' | sed -E 's/^ *AXButton d="([^,"]{1,28}).*/\1/' | tr '\n' '|'; }
nsel(){ $T/ax $P dump 9 | grep "SELECTED" | grep -vc 'd="Songs"\|d="Library"\|Up Next\|Now Playing"\|d="Albums"\|d="Artists"\|d="Genres"'; }
# center of the first element whose line contains $1 → "x y"
at(){ $T/ax $P find "$1" | head -1 | sed -E 's/.*\((-?[0-9]+),(-?[0-9]+) ([0-9]+)x([0-9]+)\)$/\1 \2 \3 \4/' | awk '{printf "%d %d", $1+$3/2, $2+$4/2}'; }
menuat(){ $T/ax $P menus | grep "^$1 " | head -1 | sed -E 's/.*\((-?[0-9]+),(-?[0-9]+) ([0-9]+)x([0-9]+)\)$/\1 \2 \3 \4/' | awk '{printf "%d %d", $1+$3/2, $2+$4/2}'; }
click(){ local xy; xy=($(at "$1")); [ -z "${xy[1]}" ] && { echo "NOT FOUND: $1"; return 1; }; $T/mc ${xy[1]} ${xy[2]} ${2:-left} $3; sleep ${4:-0.5}; }
menu(){ local xy; xy=($(menuat "$1")); [ -z "${xy[1]}" ] && { echo "MENU ITEM NOT FOUND: $1"; return 1; }; $T/mc ${xy[1]} ${xy[2]}; sleep 0.8; }
logsince(){ tail -n +$(( $1 + 1 )) $L | grep "\[UX\]" | sed 's/.*\[UX\] //'; }
# the list viewport (Songs): only click rows whose centre is inside it
VTOP=300; VBOT=730
vclick(){ local xy; xy=($(at "$1")); [ -z "${xy[1]}" ] && { echo "NOT FOUND: $1"; return 1; }
  if [ ${xy[2]} -lt $VTOP ] || [ ${xy[2]} -gt $VBOT ]; then echo "OFF-SCREEN ($1 at y=${xy[2]})"; return 1; fi
  $T/mc ${xy[1]} ${xy[2]} ${2:-left} $3; sleep ${4:-0.5}; }
# visible song rows, top to bottom (names)
visrows(){ $T/ax $P dump 9 | grep 'AXButton d=".*secs' | sed -E 's/.*d="([^,"]{1,30})[^"]*".*\((-?[0-9]+),(-?[0-9]+) [0-9]+x([0-9]+)\)$/\3 \1/' | awk -v t=$VTOP -v b=$VBOT '$1+24>=t && $1+24<=b' | cut -d' ' -f2- | tr '\n' '|'; }
# guard: bring the test app to the front and VERIFY it before any input; abort the caller otherwise
gf(){ osascript -e 'tell application "System Events" to set frontmost of process "ASTestLibrary" to true' >/dev/null 2>&1; sleep 0.4
  local f; f=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)
  [ "$f" = "ASTestLibrary" ] || { echo "ABORT: frontmost is '$f', not the test app"; return 1; }; }
hdr(){ $T/ax $P dump 8 | grep -E 'AXStaticText v="[^"]+" \(7[0-9][0-9],23' | sed -E 's/.*v="([^"]+)".*/\1/'; }
pv(){ $T/pts $P "${1:-Equalizer graph}" | sed 's/ hertz/Hz/g; s/ kilohertz/k/g; s/ decibels//g; s/ decibel//g; s/plus /+/g; s/minus /-/g'; }

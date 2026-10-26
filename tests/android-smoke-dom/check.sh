#!/bin/sh
# android-smoke: the smoke test keeps the page's DOM when its text never shows (pwa#166)
# Here smoke-test.sh, the one create_android_locked wrote, runs against a
# stand-in adb (and a no-op sleep, so the two minutes of waiting take no time) and a
# stand-in for the WebView's DevTools endpoint (server.py), and
#   1. a text never on the screen: the script fails, and the output directory holds
#      dom.html next to ui.xml, screenshot.png and logcat.txt, with the page's
#      document (a continuation frame and a ping between its halves, 100000
#      bytes) after a line naming the page, the forward made and removed;
#   2. a text on the screen: no dom.html;
#   3. no DevTools socket in the app's process: dom.html says so;
#   4. a page that never answers: dom.html says so;
#   5. (pwa#154) a text on the screen: the system font scale is set to 1.3 and 2.0
#      and back to 1.0, the page's text read at each, and the script passes when
#      the text is that many times as high and fits the window; it fails (and
#      says why) when the text stays as high (a shell that set textZoom), when the
#      page is wider than the window, when the text spans past the window, and
#      when the page never answers.
#   6. (pwa#201) "on the screen" is the page's own answer over DevTools, not the
#      accessibility tree: a dump that never holds the text while the page has it
#      passes (and the font scale step runs); a dump that holds the text while the
#      page lacks it, or has it hidden, fails; the failure line says how many polls
#      were made, when the last was and what it answered.
#   7. (pwa#207) a console error fails the script, Capacitor's early triggerEvent one
#      (the lines of the failing run, quire run 40219569509) included, before or after
#      bridge.js is served: nothing is classified or allowed.
#   9. (pwa#205) the app's probes, files next to the script: a probe that answers a point
#      records one input swipe at it, a long press; no probe file makes no
#      input call; a probe that answers nothing, or not a point, fails the run naming the
#      step; three points tapped in order and a result of true pass; a result naming a
#      missed button fails naming it; no tap probe files make no tap; the long press is
#      before the taps; one of the two tap probes alone fails.
# usage: tests/android-smoke-dom/check.sh <smoke-test.sh>
set -eu
# the wait of shown(), two minutes in a run, seconds here
SMOKE_WAIT_S=5
export SMOKE_WAIT_S
HERE=$(cd "$(dirname "$0")" && pwd)
[ $# = 1 ] || { echo "usage: $0 <smoke-test.sh>" >&2; exit 2; }
SCRIPT=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
SERVER=
trap '[ -z "$SERVER" ] || kill "$SERVER" 2>/dev/null || true; rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; shift; for f in "$@"; do echo "--- $f"; cat "$f"; done; exit 1; }

mkdir -p "$TMP/bin"
cat > "$TMP/bin/sleep" <<'STUB'
#!/bin/sh
exit 0
STUB
# adb: what the script asks of a device, answered from files of the test
cat > "$TMP/bin/adb" <<'STUB'
#!/bin/sh
echo "adb $*" >> "$STUB_LOG"
case "$*" in
  "shell getprop sys.boot_completed") echo 1 ;;
  "shell am get-started-user-state 0")
    # STUB_LOCKED_POLLS answers RUNNING_LOCKED, then RUNNING_UNLOCKED
    polls=$(cat "$STUB_POLLS" 2>/dev/null || echo 0)
    echo $((polls + 1)) > "$STUB_POLLS"
    if [ "$polls" -lt "${STUB_LOCKED_POLLS:-0}" ]; then echo RUNNING_LOCKED; else echo RUNNING_UNLOCKED; fi ;;
  "shell cat /sdcard/ui.xml") cat "$STUB_UI" ;;
  "shell settings put system font_scale "*) echo "${6}" > "$STUB_SCALE" ;;
  "shell pidof "*) echo 4242 ;;
  "shell cat /proc/net/unix") cat "$STUB_UNIX" ;;
  "forward tcp:0 localabstract:"*) echo "$(cat "$STUB_PORTFILE")" ;;
  "exec-out screencap -p") printf 'PNG' ;;
  "logcat -d -s BatsFiles:I") echo "I BatsFiles: volume key: the page" ;;
  "logcat -d") echo "I something: logcat"; if [ -n "${STUB_LOGCAT:-}" ]; then cat "$STUB_LOGCAT"; fi ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/sleep" "$TMP/bin/adb"
: > "$TMP/screen-without-text.xml"
echo '<node text="Example App" />' > "$TMP/screen-without-text.xml"
echo '<node text="BATS PWA" />' > "$TMP/screen-with-text.xml"
echo '<node text="NEVER ON SCREEN" />' > "$TMP/screen-with-other-text.xml"
UNIX_ROW='00000000: 00000002 00000000 00010000 0001 01 0 @webview_devtools_remote_'
printf '%s4242\n' "$UNIX_ROW" > "$TMP/unix-with-socket"
printf '%s1\n' "$UNIX_ROW" > "$TMP/unix-without-socket"
: > "$TMP/apk.apk"

# probe <dir> <file> <answer>: an app's probe file in the directory $TMP/probes/<dir> that
# the stand-in DevTools answers with <answer> (pwa#205)
probe() {
  mkdir -p "$TMP/probes/$1"
  printf '// stand-in answer\n%s' "$3" > "$TMP/probes/$1/$2"
}

# run <name> <mode> <ui> <unix> <text> [<probes>]: the script's output in $TMP/<name>, its
# status in $TMP/<name>.status; the script runs from a directory of its own holding the
# probe files of $TMP/probes/<probes> (none when it is not given), as an app's are next to it
run() {
  name=$1; mode=$2
  mkdir -p "$TMP/$name.dir"
  cp "$SCRIPT" "$TMP/$name.dir/smoke-test.sh"
  if [ -n "${6:-}" ]; then cp "$TMP/probes/$6"/* "$TMP/$name.dir/"; fi
  rm -f "$TMP/port"
  rm -f "$TMP/scale"
  python3 "$HERE/server.py" "$TMP/port" "$mode" "$TMP/scale" &
  SERVER=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMP/port" ] && break; /bin/sleep 1; done
  [ -s "$TMP/port" ] || fail "the DevTools stand-in did not start"
  : > "$TMP/$name.log"
  status=0
  PATH="$TMP/bin:$PATH" STUB_LOG="$TMP/$name.log" STUB_UI="$TMP/$3" STUB_UNIX="$TMP/$4" \
    STUB_PORTFILE="$TMP/port" STUB_SCALE="$TMP/scale" STUB_POLLS="$TMP/$name.polls" timeout 120 sh "$TMP/$name.dir/smoke-test.sh" "$TMP/apk.apk" "$5" "$TMP/$name" \
    < /dev/null > "$TMP/$name.out" 2>&1 || status=$?
  kill "$SERVER" 2>/dev/null || true
  SERVER=
  echo "$status" > "$TMP/$name.status"
}

# SMOKE_CASE=<name> runs one of the probe cases of 9 alone (a few seconds), for the injections
# of the script that show each fails when its class occurs (pwa#205)
want() { [ -z "${SMOKE_CASE:-}" ] || [ "$SMOKE_CASE" = "$1" ]; }
if [ -z "${SMOKE_CASE:-}" ]; then
# 1. a text never on the screen
run absent ok screen-without-text.xml unix-with-socket "NEVER ON SCREEN"
[ "$(cat "$TMP/absent.status")" = 1 ] ||
  fail "the script did not fail on a text never shown" "$TMP/absent.out"
grep -q "'NEVER ON SCREEN' was not on the screen" "$TMP/absent.out" ||
  fail "no message" "$TMP/absent.out"
grep -Eq "after two minutes: [0-9]+ DevTools polls, the last at [0-9:]+ answered 'false'" "$TMP/absent.out" ||
  fail "the failure line does not give the polls, the time of the last and its answer" "$TMP/absent.out"
grep "was not on the screen" "$TMP/absent.out"
for f in ui.xml screenshot.png logcat.txt dom.html; do
  [ -s "$TMP/absent/$f" ] || fail "$f is not in the output directory" "$TMP/absent.out"
done
ls -l "$TMP/absent"
grep -q '^<!-- page: page https://localhost/ -->$' "$TMP/absent/dom.html" ||
  fail "no page line" "$TMP/absent/dom.html"
grep -q '<div id="bats-root">BATS PWA</div>' "$TMP/absent/dom.html" ||
  fail "no bats-root" "$TMP/absent/dom.html"
case "$(cat "$TMP/absent/dom.html")" in
  *"service_worker"*) fail "a page without a socket was listed" ;;
esac
[ "$(wc -c < "$TMP/absent/dom.html")" -gt 100000 ] || fail "the document is cut short"
grep -q '^adb forward tcp:0 localabstract:webview_devtools_remote_4242$' "$TMP/absent.log" ||
  fail "no forward" "$TMP/absent.log"
grep -q '^adb forward --remove tcp:' "$TMP/absent.log" ||
  fail "forward not removed" "$TMP/absent.log"
head -c 300 "$TMP/absent/dom.html"; echo

# 2. a text on the screen: nothing is kept
run present ok screen-with-text.xml unix-with-socket "BATS PWA"
[ "$(cat "$TMP/present.status")" = 0 ] ||
  fail "the script failed on a text shown" "$TMP/present.out"
[ ! -e "$TMP/present/dom.html" ] || fail "dom.html is kept when the text shows"
# no forward for the DOM, and each forward of the font scale probes removed
[ "$(grep -c '^adb forward tcp:0' "$TMP/present.log")" = "$(grep -c '^adb forward --remove' "$TMP/present.log")" ] ||
  fail "a forward was left" "$TMP/present.log"

# 2b. (pwa#201) the dump never holds the text, the page has it: shown
run drawn ok screen-without-text.xml unix-with-socket "BATS PWA"
[ "$(cat "$TMP/drawn.status")" = 0 ] ||
  fail "the script failed on a page with the text whose dump never shows it" "$TMP/drawn.out"
grep -q "^'BATS PWA' is on the screen$" "$TMP/drawn.out" || fail "not said shown" "$TMP/drawn.out"
[ ! -e "$TMP/drawn/dom.html" ] || fail "dom.html is kept when the text shows"
if grep -q 'uiautomator' "$TMP/drawn.log"; then fail "the accessibility tree was asked for a page that shows" "$TMP/drawn.log"; fi
grep -q 'Font scale 2.0: ratio' "$TMP/drawn.out" || fail "the font scale step did not run" "$TMP/drawn.out"

# 2c. the dump holds the text, the page lacks it: not shown; 2d. the text is in a hidden page
run lacking ok screen-with-other-text.xml unix-with-socket "NEVER ON SCREEN"
[ "$(cat "$TMP/lacking.status")" = 1 ] ||
  fail "the script passed on a page that lacks the text its dump holds" "$TMP/lacking.out"
grep -q "'NEVER ON SCREEN' was not on the screen" "$TMP/lacking.out" || fail "no message" "$TMP/lacking.out"
[ -s "$TMP/lacking/dom.html" ] || fail "no dom.html" "$TMP/lacking.out"
run hidden hidden screen-with-text.xml unix-with-socket "BATS PWA"
[ "$(cat "$TMP/hidden.status")" = 1 ] ||
  fail "the script passed on a page that is not visible" "$TMP/hidden.out"

# 3. no socket
run nosocket ok screen-without-text.xml unix-without-socket "NEVER ON SCREEN"
grep -q '^No DevTools socket (app pid 4242)$' "$TMP/nosocket/dom.html" ||
  fail "no socket not said" "$TMP/nosocket/dom.html"

# 4. a page that never answers
run silent silent screen-without-text.xml unix-with-socket "NEVER ON SCREEN"
grep -q '^DevTools did not answer$' "$TMP/silent/dom.html" ||
  fail "silence not said" "$TMP/silent/dom.html"
grep -q '^adb forward --remove tcp:' "$TMP/silent.log" ||
  fail "forward not removed after silence" "$TMP/silent.log"

# 5. the system font scale
run scaled ok screen-with-text.xml unix-with-socket "BATS PWA"
[ "$(cat "$TMP/scaled.status")" = 0 ] || fail "the script failed at the font scales" "$TMP/scaled.out"
grep -q '^Font scale 1.3: ratio 1.30 ' "$TMP/scaled.out" || fail "no 1.3" "$TMP/scaled.out"
grep -q '^Font scale 2.0: ratio 2.00 ' "$TMP/scaled.out" || fail "no 2.0" "$TMP/scaled.out"
grep 'settings put system font_scale' "$TMP/scaled.log" | tr '\n' ' ' | grep -q 'font_scale 1.0 .*font_scale 1.3 .*font_scale 2.0 .*font_scale 1.0 $' ||
  fail "the scales were not set 1.0, 1.3, 2.0 and 1.0 again" "$TMP/scaled.log"
for mode in textzoom wide outside; do
  run "font-$mode" "$mode" screen-with-text.xml unix-with-socket "BATS PWA"
  [ "$(cat "$TMP/font-$mode.status")" = 1 ] ||
    fail "the script passed with the font scale mutant $mode" "$TMP/font-$mode.out"
done
grep -q '^Font scale 1.3: its line is 1.00 times as high as at 1.0' "$TMP/font-textzoom.out" || fail "textzoom not said" "$TMP/font-textzoom.out"
grep -q '^Font scale 1.3: the page is 462 px wide in a window of 412 px' "$TMP/font-wide.out" || fail "wide not said" "$TMP/font-wide.out"
grep -q '^Font scale 1.3: the text spans 8 to 442' "$TMP/font-outside.out" || fail "outside not said" "$TMP/font-outside.out"
run font-silent silent-probe screen-with-text.xml unix-with-socket "BATS PWA"
[ "$(cat "$TMP/font-silent.status")" = 1 ] || fail "the script passed with a silent page" "$TMP/font-silent.out"
grep -q '^Font scale 1.0: the text was never on the page' "$TMP/font-silent.out" || fail "silence not said" "$TMP/font-silent.out"
# 7. (pwa#207) no console error is classified, ignored or allowed: Capacitor's early
# triggerEvent error (the lines of the failing run) fails the script, before or after
# bridge.js is served, and so does any other
LOGCAT_DIR="$HERE/logcat"
errors() { STUB_LOGCAT="$LOGCAT_DIR/$2" run "$1" ok screen-with-text.xml unix-with-socket "BATS PWA"; }
for case in early-event late-event recreated-event other-error; do
  errors "err-$case" "$case.txt"
  [ "$(cat "$TMP/err-$case.status")" = 1 ] || fail "the script passed with the console error of $case" "$TMP/err-$case.out"
  grep -q '^The page logged console errors (above)$' "$TMP/err-$case.out" || fail "no console errors line for $case" "$TMP/err-$case.out"
  echo "case 7, $case: the script exited $(cat "$TMP/err-$case.status") and printed:"
  grep -E 'Capacitor/Console|console errors' "$TMP/err-$case.out"
done
grep -q "reading 'triggerEvent')$" "$TMP/err-early-event.out" || fail "the early triggerEvent error is not printed" "$TMP/err-early-event.out"
# 8. (pwa#207) the app is installed and launched only once user 0 is unlocked
# (am get-started-user-state 0 is RUNNING_UNLOCKED), the state after which system_server
# no longer relaunches the first activity: locked for three answers, then unlocked
STUB_LOCKED_POLLS=3 run unlocking ok screen-with-text.xml unix-with-socket "BATS PWA"
[ "$(cat "$TMP/unlocking.status")" = 0 ] || fail "the script failed once the user unlocked" "$TMP/unlocking.out"
[ "$(grep -c '^adb shell am get-started-user-state 0$' "$TMP/unlocking.log")" = 4 ] ||
  fail "the user state was not asked until it was RUNNING_UNLOCKED (four answers)" "$TMP/unlocking.log"
[ "$(grep -n '^adb shell am get-started-user-state 0$' "$TMP/unlocking.log" | tail -1 | cut -d: -f1)" -lt \
  "$(grep -n '^adb install' "$TMP/unlocking.log" | head -1 | cut -d: -f1)" ] ||
  fail "the app was installed before the user was unlocked" "$TMP/unlocking.log"
# a user that stays locked: the script installs nothing and launches nothing
rm -f "$TMP/port" "$TMP/locked.polls"; : > "$TMP/locked.log"; status=0
PATH="$TMP/bin:$PATH" STUB_LOG="$TMP/locked.log" STUB_UI="$TMP/screen-with-text.xml" STUB_UNIX="$TMP/unix-with-socket" \
  STUB_PORTFILE="$TMP/port" STUB_SCALE="$TMP/scale" STUB_POLLS="$TMP/locked.polls" STUB_LOCKED_POLLS=1000000 \
  timeout 3 sh "$SCRIPT" "$TMP/apk.apk" "BATS PWA" "$TMP/locked" < /dev/null > "$TMP/locked.out" 2>&1 || status=$?
[ "$status" = 124 ] || fail "the script went on with a user that stays locked (status $status)" "$TMP/locked.out"
if grep -q '^adb install' "$TMP/locked.log"; then fail "the app was installed for a locked user" "$TMP/locked.log"; fi
echo "case 8: a user that stays locked: the script was ended by timeout (status $status), asked the user state $(grep -c '^adb shell am get-started-user-state 0$' "$TMP/locked.log") times, installed nothing"
echo "case 8: a user locked for three answers: $(grep -c '^adb shell am get-started-user-state 0$' "$TMP/unlocking.log") polls, then the install"
fi
# 9. (pwa#205) the app's probes: files next to the script that the page answers over DevTools
INPUTS="^adb shell input (swipe|tap) "
probe select smoke-select-point.js "540 1200"
if want longpress; then
run longpress ok screen-with-text.xml unix-with-socket "BATS PWA" select
[ "$(cat "$TMP/longpress.status")" = 0 ] || fail "the script failed with a probe that answers a point" "$TMP/longpress.out"
[ "$(grep -c -E "$INPUTS" "$TMP/longpress.log")" = 1 ] || fail "not one input call for one point" "$TMP/longpress.log"
grep -qx 'adb shell input swipe 540 1200 540 1200 1000' "$TMP/longpress.log" ||
  fail "no long press of 1000 ms at the point" "$TMP/longpress.log"
echo "case 9, a probe answering '540 1200': $(grep -E "$INPUTS" "$TMP/longpress.log")"
fi
if want noprobe; then
run noprobe ok screen-with-text.xml unix-with-socket "BATS PWA"
[ "$(cat "$TMP/noprobe.status")" = 0 ] || fail "the script failed with no probe file" "$TMP/noprobe.out"
if grep -q -E "$INPUTS" "$TMP/noprobe.log"; then fail "an input call with no probe file" "$TMP/noprobe.log"; fi
echo "case 9, no probe file: $(grep -c -E "$INPUTS" "$TMP/noprobe.log") input calls"
fi
if want pressnothing; then
probe nothing smoke-select-point.js ""
run pressnothing ok screen-with-text.xml unix-with-socket "BATS PWA" nothing
[ "$(cat "$TMP/pressnothing.status")" = 1 ] || fail "the script passed with a probe that answers nothing" "$TMP/pressnothing.out"
grep -q "^Long press: smoke-select-point.js answered '', not x and y in device pixels$" "$TMP/pressnothing.out" ||
  fail "the failure does not name the step" "$TMP/pressnothing.out"
if grep -q -E "$INPUTS" "$TMP/pressnothing.log"; then fail "a long press with no point" "$TMP/pressnothing.log"; fi
echo "case 9, a probe answering nothing: $(grep '^Long press' "$TMP/pressnothing.out")"
fi
if want presswords; then
probe notpoint smoke-select-point.js "left 10"
run presswords ok screen-with-text.xml unix-with-socket "BATS PWA" notpoint
[ "$(cat "$TMP/presswords.status")" = 1 ] || fail "the script passed with a probe that answers words" "$TMP/presswords.out"
grep -q "^Long press: smoke-select-point.js answered 'left 10'" "$TMP/presswords.out" || fail "words not said" "$TMP/presswords.out"
fi
if want presssilent; then
run presssilent silent-probe screen-with-text.xml unix-with-socket "BATS PWA" select
[ "$(cat "$TMP/presssilent.status")" = 1 ] || fail "the script passed with a silent page" "$TMP/presssilent.out"
grep -q "^Long press: smoke-select-point.js answered 'DevTools did not answer'" "$TMP/presssilent.out" ||
  fail "a silent page is not said at the long press" "$TMP/presssilent.out"
fi
if want tapped; then
probe taps smoke-select-point.js "540 1200"
probe taps smoke-tap-points.js "back 100 200
save 300.5 400
share 500 600"
probe taps smoke-tap-result.js "true"
run tapped ok screen-with-text.xml unix-with-socket "BATS PWA" taps
[ "$(cat "$TMP/tapped.status")" = 0 ] || fail "the script failed with three points tapped and a result of true" "$TMP/tapped.out"
[ "$(grep -c -E "$INPUTS" "$TMP/tapped.log")" = 4 ] || fail "not a long press and three taps" "$TMP/tapped.log"
grep -E "$INPUTS" "$TMP/tapped.log" > "$TMP/tapped.inputs"
printf '%s\n' 'adb shell input swipe 540 1200 540 1200 1000' 'adb shell input tap 100 200' \
  'adb shell input tap 300 400' 'adb shell input tap 500 600' > "$TMP/tapped.want"
cmp -s "$TMP/tapped.inputs" "$TMP/tapped.want" || fail "the long press and the taps are not in order, at the points" "$TMP/tapped.inputs" "$TMP/tapped.want"
echo "case 9, three points and a result of true: the script exited 0 and called"
cat "$TMP/tapped.inputs"
fi
if want tapmissed; then
probe missed smoke-select-point.js "540 1200"
probe missed smoke-tap-points.js "back 100 200
save 300 400
share 500 600"
probe missed smoke-tap-result.js "save
share"
run tapmissed ok screen-with-text.xml unix-with-socket "BATS PWA" missed
[ "$(cat "$TMP/tapmissed.status")" = 1 ] || fail "the script passed with buttons the page did not see clicked" "$TMP/tapmissed.out"
grep -q '^Taps: the page saw no click on: save share $' "$TMP/tapmissed.out" || fail "the missed buttons are not named" "$TMP/tapmissed.out"
echo "case 9, a result naming missed buttons: $(grep '^Taps' "$TMP/tapmissed.out")"
fi
if want tapsonly; then
probe tapsonly smoke-tap-points.js "back 100 200"
probe tapsonly smoke-tap-result.js "true"
run tapsonly ok screen-with-text.xml unix-with-socket "BATS PWA" tapsonly
[ "$(cat "$TMP/tapsonly.status")" = 0 ] || fail "the script failed with taps and no long press" "$TMP/tapsonly.out"
[ "$(grep -c -E "$INPUTS" "$TMP/tapsonly.log")" = 1 ] || fail "not one tap" "$TMP/tapsonly.log"
if grep -q 'input swipe' "$TMP/tapsonly.log"; then fail "a long press with no select probe" "$TMP/tapsonly.log"; fi
run notaps ok screen-with-text.xml unix-with-socket "BATS PWA" select
if grep -q 'input tap' "$TMP/notaps.log"; then fail "a tap with no tap probe files" "$TMP/notaps.log"; fi
echo "case 9, no tap probe files: $(grep -c 'input tap' "$TMP/notaps.log") taps"
fi
if want tapsnothing; then
probe nopoints smoke-tap-points.js ""
probe nopoints smoke-tap-result.js "true"
run tapsnothing ok screen-with-text.xml unix-with-socket "BATS PWA" nopoints
[ "$(cat "$TMP/tapsnothing.status")" = 1 ] || fail "the script passed with a tap probe that names no button" "$TMP/tapsnothing.out"
grep -q "^Taps: smoke-tap-points.js named no button" "$TMP/tapsnothing.out" || fail "no button not said" "$TMP/tapsnothing.out"
fi
if want tapbad; then
probe badline smoke-tap-points.js "back 100 200
save left top"
probe badline smoke-tap-result.js "true"
run tapbad ok screen-with-text.xml unix-with-socket "BATS PWA" badline
[ "$(cat "$TMP/tapbad.status")" = 1 ] || fail "the script passed with a tap line that is not a point" "$TMP/tapbad.out"
grep -q "^Taps: smoke-tap-points.js answered the line 'save left top '" "$TMP/tapbad.out" || fail "bad line not said" "$TMP/tapbad.out"
fi
if want tapspair; then
probe pointsonly smoke-tap-points.js "back 100 200"
run tapspair ok screen-with-text.xml unix-with-socket "BATS PWA" pointsonly
[ "$(cat "$TMP/tapspair.status")" = 1 ] || fail "the script passed with one of the two tap probes" "$TMP/tapspair.out"
grep -q '^Taps: smoke-tap-points.js and smoke-tap-result.js go together, and one is missing$' "$TMP/tapspair.out" || fail "the pair not said" "$TMP/tapspair.out"
fi
if [ -z "${SMOKE_CASE:-}" ]; then echo "OK: the page's DOM is kept when the text never shows, and the font scale reaches the page"; else echo "OK: case $SMOKE_CASE"; fi

#!/bin/sh
# android-smoke: the smoke test keeps the page's DOM when its text never shows (pwa#166)
# Here smoke-test.sh, the one create_android wrote, runs against a
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
#   7. (pwa#207) Capacitor's own pause/resume event, evaluated in the web view as
#      window.Capacitor.triggerEvent(...) before bridge.js is served for the page
#      (the lines of the failing run, quire run 40219569509): said and kept in
#      early-events.txt, not a failure; the same line once bridge.js is served, and any
#      other console error before it, fail; a page the activity loads again in the same
#      process is judged on its own.
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

# run <name> <mode> <ui> <unix> <text>: the script's output in $TMP/<name>, its
# status in $TMP/<name>.status
run() {
  name=$1; mode=$2
  rm -f "$TMP/port"
  rm -f "$TMP/scale"
  python3 "$HERE/server.py" "$TMP/port" "$mode" "$TMP/scale" &
  SERVER=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMP/port" ] && break; /bin/sleep 1; done
  [ -s "$TMP/port" ] || fail "the DevTools stand-in did not start"
  : > "$TMP/$name.log"
  status=0
  PATH="$TMP/bin:$PATH" STUB_LOG="$TMP/$name.log" STUB_UI="$TMP/$3" STUB_UNIX="$TMP/$4" \
    STUB_PORTFILE="$TMP/port" STUB_SCALE="$TMP/scale" timeout 120 sh "$SCRIPT" "$TMP/apk.apk" "$5" "$TMP/$name" \
    < /dev/null > "$TMP/$name.out" 2>&1 || status=$?
  kill "$SERVER" 2>/dev/null || true
  SERVER=
  echo "$status" > "$TMP/$name.status"
}

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
# 7. Capacitor's early lifecycle event (pwa#207): STUB_LOGCAT is what the device's logcat holds
LOGCAT_DIR="$HERE/logcat"
early() { STUB_LOGCAT="$LOGCAT_DIR/$2" run "$1" ok screen-with-text.xml unix-with-socket "BATS PWA"; }
early early early-event.txt
[ "$(cat "$TMP/early.status")" = 0 ] || fail "the script failed on Capacitor's early event" "$TMP/early.out"
grep -q "^Not a failure, Capacitor's own lifecycle event before bridge.js was served (pwa#207):$" "$TMP/early.out" || fail "the early event was not said" "$TMP/early.out"
grep -q "reading 'triggerEvent')$" "$TMP/early/early-events.txt" || fail "the early event is not kept" "$TMP/early/early-events.txt"
if grep -q "console errors" "$TMP/early.out"; then fail "the early event was counted as a console error" "$TMP/early.out"; fi
early recreated recreated-event.txt
[ "$(cat "$TMP/recreated.status")" = 0 ] || fail "the script failed on the early event of a page loaded again" "$TMP/recreated.out"
early late late-event.txt
[ "$(cat "$TMP/late.status")" = 1 ] || fail "the script passed on the triggerEvent error after bridge.js was served" "$TMP/late.out"
grep -q '^The page logged console errors (above)$' "$TMP/late.out" || fail "no console errors line" "$TMP/late.out"
[ ! -s "$TMP/late/early-events.txt" ] || fail "an error after bridge.js was kept as early" "$TMP/late/early-events.txt"
early other other-error.txt
[ "$(cat "$TMP/other.status")" = 1 ] || fail "the script passed on another console error before bridge.js" "$TMP/other.out"
grep -q 'Uncaught ReferenceError: x is not defined' "$TMP/other.out" || fail "the error is not printed" "$TMP/other.out"
echo "OK: the page's DOM is kept when the text never shows, and the font scale reaches the page"

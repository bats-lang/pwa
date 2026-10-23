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
#   4. a page that never answers: dom.html says so.
# usage: tests/android-smoke-dom/check.sh <smoke-test.sh>
set -eu
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
  "shell pidof "*) echo 4242 ;;
  "shell cat /proc/net/unix") cat "$STUB_UNIX" ;;
  "forward tcp:0 localabstract:"*) echo "$(cat "$STUB_PORTFILE")" ;;
  "exec-out screencap -p") printf 'PNG' ;;
  "logcat -d -s BatsFiles:I") echo "I BatsFiles: volume key: the page" ;;
  "logcat -d") echo "I something: logcat" ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/sleep" "$TMP/bin/adb"
: > "$TMP/screen-without-text.xml"
echo '<node text="Example App" />' > "$TMP/screen-without-text.xml"
echo '<node text="BATS PWA" />' > "$TMP/screen-with-text.xml"
UNIX_ROW='00000000: 00000002 00000000 00010000 0001 01 0 @webview_devtools_remote_'
printf '%s4242\n' "$UNIX_ROW" > "$TMP/unix-with-socket"
printf '%s1\n' "$UNIX_ROW" > "$TMP/unix-without-socket"
: > "$TMP/apk.apk"

# run <name> <mode> <ui> <unix> <text>: the script's output in $TMP/<name>, its
# status in $TMP/<name>.status
run() {
  name=$1; mode=$2
  rm -f "$TMP/port"
  python3 "$HERE/server.py" "$TMP/port" "$mode" &
  SERVER=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMP/port" ] && break; /bin/sleep 1; done
  [ -s "$TMP/port" ] || fail "the DevTools stand-in did not start"
  : > "$TMP/$name.log"
  status=0
  PATH="$TMP/bin:$PATH" STUB_LOG="$TMP/$name.log" STUB_UI="$TMP/$3" STUB_UNIX="$TMP/$4" \
    STUB_PORTFILE="$TMP/port" timeout 120 sh "$SCRIPT" "$TMP/apk.apk" "$5" "$TMP/$name" \
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
if grep -q 'forward' "$TMP/present.log"; then
  fail "a forward was made for a passing run" "$TMP/present.log"
fi

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
echo "OK: the page's DOM is kept when the text never shows"

#!/bin/sh
# gen-pwa test (bats-lang/pwa#82), with a stand-in Playwright that
# records its arguments and environment, fetches the app it is pointed
# at, and sleeps. Checked: the app is served at the port handed over and
# the port is free after the run; two runs at once take turns, the
# second saying it waits; after kill -TERM of gen-pwa, and after a
# failing run, nothing serves and no stand-in is left; the @serial run
# has one worker; --timings names the JSON files; a caller's --workers
# makes one run; a browser older than Playwright expects, or none, is
# said, with both revisions.
# usage: tests/test-command/check.sh <gen-pwa binary> <built dist/pwa>
set -eu
GEN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
PWA=$(cd "$2" && pwd)
TMP=$(mktemp -d)
cleanup() { pkill -f "$TMP/fake-pw" 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT
P=$TMP/proj
mkdir -p "$P/dist" "$P/node_modules/playwright-core" "$TMP/browsers/chromium_headless_shell-1194"
cp -R "$PWA" "$P/dist/pwa"
printf '{"name":"playwright-core","version":"1.56.1"}\n' > "$P/node_modules/playwright-core/package.json"
browsers_json() { printf '{"browsers":[{"name":"chromium-headless-shell","revision":"%s"}]}\n' "$1" > "$P/node_modules/playwright-core/browsers.json"; }
browsers_json 1194
cat > "$TMP/fake-pw" <<'FAKE'
#!/bin/sh
log=$FAKE_PW_LOG
{ echo "start $$ $*"; echo "url $PWA_TEST_BASE_URL"; echo "browsers $PLAYWRIGHT_BROWSERS_PATH"; echo "json ${PLAYWRIGHT_JSON_OUTPUT_NAME:-}"; } >> "$log"
node -e "fetch(process.env.PWA_TEST_BASE_URL + '/app.wasm').then(r => console.log('fetched', r.status, r.headers.get('content-type')))" >> "$log" 2>&1
sleep "${FAKE_PW_SLEEP:-0}"
echo "end $$" >> "$log"
exit "${FAKE_PW_EXIT:-0}"
FAKE
chmod +x "$TMP/fake-pw"
export PWA_TEST_PLAYWRIGHT="$TMP/fake-pw" PWA_TEST_LOCK_DIR="$TMP/locks" PLAYWRIGHT_BROWSERS_PATH="$TMP/browsers"
unset PWA_TEST_SLOTS
cd "$P"
run() { # <log> <gen-pwa test args...>
  log=$1; shift
  FAKE_PW_LOG="$log" "$GEN" test "$@"
}
closed() { # <port>: nothing listens on it
  node -e "require('net').connect($1, '127.0.0.1').on('connect', () => process.exit(1)).on('error', () => process.exit(0))"
}
ports() { sed -n 's|^url http://127.0.0.1:||p' "$1"; }

# a run: served at the port handed over, serial set first on one worker
run "$TMP/a.log" --timings "$TMP/times" -- --project x > "$TMP/a.out" 2>&1 || { echo "FAIL: a passing run"; cat "$TMP/a.out" "$TMP/a.log"; exit 1; }
[ "$(grep -c '^fetched 200 application/wasm' "$TMP/a.log")" = 2 ] || { echo "FAIL: dist/pwa not served as wasm"; cat "$TMP/a.log"; exit 1; }
grep -q '^start [0-9]* test --grep @serial --workers=1 --pass-with-no-tests --reporter=list,json --project x$' "$TMP/a.log" || { echo "FAIL: the serial run"; cat "$TMP/a.log"; exit 1; }
grep -q '^start [0-9]* test --grep-invert @serial --workers=[0-9]* --pass-with-no-tests --reporter=list,json --project x$' "$TMP/a.log" || { echo "FAIL: the parallel run"; cat "$TMP/a.log"; exit 1; }
grep -q "^json $TMP/times/serial.json$" "$TMP/a.log" && grep -q "^json $TMP/times/parallel.json$" "$TMP/a.log" || { echo "FAIL: --timings"; cat "$TMP/a.log"; exit 1; }
grep -q "^browsers $TMP/browsers$" "$TMP/a.log" || { echo "FAIL: the browsers' location"; exit 1; }
for p in $(ports "$TMP/a.log"); do closed "$p" || { echo "FAIL: port $p still served after the run"; exit 1; }; done

# a caller's --workers: one run, as given
run "$TMP/w.log" -- --workers=3 > "$TMP/w.out" 2>&1 || { echo "FAIL: a run with --workers"; cat "$TMP/w.out"; exit 1; }
[ "$(grep -c '^start' "$TMP/w.log")" = 1 ] && grep -q '^start [0-9]* test --workers=[0-9]* --workers=3$' "$TMP/w.log" || { echo "FAIL: --workers of the caller"; cat "$TMP/w.log"; exit 1; }

# two at once take turns
FAKE_PW_SLEEP=2 run "$TMP/two.log" > "$TMP/one.out" 2>&1 &
first=$!
sleep 1
FAKE_PW_SLEEP=2 run "$TMP/two.log" > "$TMP/second.out" 2>&1 &
second=$!
wait $first || { echo "FAIL: the first of two"; cat "$TMP/one.out"; exit 1; }
wait $second || { echo "FAIL: the second of two"; cat "$TMP/second.out"; exit 1; }
grep -q "waiting for another gen-pwa test" "$TMP/second.out" || { echo "FAIL: the second did not say it waited"; cat "$TMP/second.out"; exit 1; }
awk '$1 == "start" { if (open != "") { print "overlap"; bad = 1 } open = $2 } $1 == "end" { open = "" } END { exit bad }' "$TMP/two.log" || { echo "FAIL: two runs at once"; cat "$TMP/two.log"; exit 1; }

# kill -TERM of gen-pwa mid-run: no server, no stand-in left
(FAKE_PW_SLEEP=30 FAKE_PW_LOG="$TMP/k.log" exec "$GEN" test > "$TMP/k.out" 2>&1) &
gen=$!
i=0; while ! grep -q '^fetched' "$TMP/k.log" 2>/dev/null; do i=$((i + 1)); [ $i -lt 100 ] || { echo "FAIL: the run did not start"; exit 1; }; sleep 0.2; done
kill -TERM $gen
wait $gen 2>/dev/null || true
i=0; while pgrep -f "$TMP/fake-pw" > /dev/null; do i=$((i + 1)); [ $i -lt 50 ] || { echo "FAIL: the stand-in outlived gen-pwa"; pgrep -af "$TMP/fake-pw"; exit 1; }; sleep 0.2; done
for p in $(ports "$TMP/k.log"); do closed "$p" || { echo "FAIL: port $p still served after kill -TERM"; exit 1; }; done
if pgrep -f "gen-pwa test: cannot serve" > /dev/null || pgrep -f "http.createServer" > /dev/null; then echo "FAIL: a keeper is left"; exit 1; fi

# a failing run: its status, and nothing left
if FAKE_PW_EXIT=1 run "$TMP/f.log" > "$TMP/f.out" 2>&1; then echo "FAIL: a failing run passed"; exit 1; fi
grep -q "tests failed" "$TMP/f.out" || { echo "FAIL: a failing run not said"; cat "$TMP/f.out"; exit 1; }
for p in $(ports "$TMP/f.log"); do closed "$p" || { echo "FAIL: port $p still served after a failing run"; exit 1; }; done

# browsers older than Playwright expects, then none: said, nothing run
browsers_json 1300
if run "$TMP/o.log" > "$TMP/o.out" 2>&1; then echo "FAIL: ran with an older browser"; exit 1; fi
grep -q "older than this Playwright expects" "$TMP/o.out" && grep -q "chromium_headless_shell-1300" "$TMP/o.out" && grep -q "1194" "$TMP/o.out" || { echo "FAIL: an older browser not said"; cat "$TMP/o.out"; exit 1; }
[ ! -e "$TMP/o.log" ] || { echo "FAIL: Playwright ran with an older browser"; exit 1; }
rm -rf "$TMP/browsers/chromium_headless_shell-1194"
if run "$TMP/m.log" > "$TMP/m.out" 2>&1; then echo "FAIL: ran with no browser"; exit 1; fi
grep -q "is not installed" "$TMP/m.out" || { echo "FAIL: a missing browser not said"; cat "$TMP/m.out"; exit 1; }
echo "test-command: ok"

#!/bin/sh
# gen-pwa test (bats-lang/pwa#82), with a stand-in Playwright that
# records its arguments and environment, fetches the app it is pointed
# at, and sleeps. Checked: the app is served at the port handed over and
# the port is free after the run; two runs at once take turns, the
# second saying it waits; after kill -TERM of gen-pwa, and after a
# failing run, nothing serves and no stand-in is left; the @serial run
# has one worker; --timings names the JSON files; a caller's --workers
# makes one run; a browser older than Playwright expects, or none, is
# said, with both revisions; a path with a NUL does not stop the server;
# without --timings the caller's own JSON report is left alone; an
# unknown option is said; a Playwright older than 1.58, and one whose
# version cannot be read, is refused and said (bats-lang/pwa#92); a
# Playwright that exits 70, 71 or 143 is a failed run, and a keeper killed
# by a signal is said as one whose exit status could not be read (bats-lang/pwa#84);
# a lock that cannot be taken is refused and said, nothing run (bats-lang/pwa#155).
# usage: tests/test-command/check.sh <gen-pwa binary> <built dist/pwa>
set -eu
GEN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
PWA=$(cd "$2" && pwd)
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
cleanup() { pkill -f "$TMP/fake-pw" 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT
P=$TMP/proj
mkdir -p "$P/dist" "$P/node_modules/playwright-core" "$TMP/browsers/chromium_headless_shell-1194"
cp -R "$PWA" "$P/dist/pwa"
printf '{"name":"playwright-core","version":"1.58.2"}\n' > "$P/node_modules/playwright-core/package.json"
browsers_json() { printf '{"browsers":[{"name":"chromium-headless-shell","revision":"%s"}]}\n' "$1" > "$P/node_modules/playwright-core/browsers.json"; }
browsers_json 1194
cat > "$TMP/fake-pw" <<'FAKE'
#!/bin/sh
log=$FAKE_PW_LOG
echo "keeper $PPID" >> "$log"
{ echo "start $$ $*"; echo "url $PWA_TEST_BASE_URL"; echo "browsers $PLAYWRIGHT_BROWSERS_PATH"; echo "json ${PLAYWRIGHT_JSON_OUTPUT_NAME:-}"; echo "evidence ${PWA_TEST_EVIDENCE_DIR:-}"; echo "options ${NODE_OPTIONS:-}"; echo "source-left ${PWA_TEST_WATCH_SOURCE:+yes}"; } >> "$log"
# the page watch (bats-lang/pwa#230): the preload NODE_OPTIONS names is copied out for the tests of it
if [ -n "${FAKE_PW_COPY_WATCH:-}" ]; then f=${NODE_OPTIONS#*--require=\"}; f=${f%%\"*}; cp "$f" "$FAKE_PW_COPY_WATCH"; echo "watch-existed $f" >> "$log"; fi
node -e "fetch(process.env.PWA_TEST_BASE_URL + '/app.wasm').then(r => console.log('fetched', r.status, r.headers.get('content-type')))" >> "$log" 2>&1
# a path with a NUL is refused, and the server goes on serving
node -e "fetch(process.env.PWA_TEST_BASE_URL + '/%00').then(r => console.log('nul', r.status)).then(() => fetch(process.env.PWA_TEST_BASE_URL + '/')).then(r => console.log('after nul', r.status))" >> "$log" 2>&1
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
[ "$(grep -c '^nul 400$' "$TMP/a.log")" = 2 ] && [ "$(grep -c '^after nul 200$' "$TMP/a.log")" = 2 ] || { echo "FAIL: a path with a NUL"; cat "$TMP/a.log"; exit 1; }

# without --timings, the caller's own JSON report stays where it named it
PLAYWRIGHT_JSON_OUTPUT_NAME="$TMP/own.json" run "$TMP/j.log" > "$TMP/j.out" 2>&1 || { echo "FAIL: a run without --timings"; cat "$TMP/j.out"; exit 1; }
[ "$(grep -c "^json $TMP/own.json$" "$TMP/j.log")" = 2 ] || { echo "FAIL: PLAYWRIGHT_JSON_OUTPUT_NAME replaced without --timings"; cat "$TMP/j.log"; exit 1; }
if grep -q -- '--reporter' "$TMP/j.log"; then echo "FAIL: a reporter added without --timings"; exit 1; fi

# an option gen-pwa test does not know: said, nothing run
if run "$TMP/u.log" --timing x > "$TMP/u.out" 2>&1; then echo "FAIL: an unknown option ran"; exit 1; fi
grep -q "unknown option '--timing'" "$TMP/u.out" || { echo "FAIL: an unknown option not said"; cat "$TMP/u.out"; exit 1; }
[ ! -e "$TMP/u.log" ] || { echo "FAIL: Playwright ran with an unknown option"; exit 1; }

# a lock that cannot be taken (bats-lang/pwa#155): refused, said, exit 1,
# nothing run. NoLockDir: the lock's directory is under a file, so it cannot
# be made. NoLockFile: slot-0.lock is a directory, so it cannot be opened
# (root too). LockUnsupported (a file system with no locks) cannot be made
# here; its mapping is tested in the bats test block of src/test_run.bats.
: > "$TMP/notdir"
PWA_TEST_LOCK_DIR="$TMP/notdir/locks" FAKE_PW_LOG="$TMP/nd.log" "$GEN" test > "$TMP/nd.out" 2>&1 && { echo "FAIL: a run with no lock directory ran"; cat "$TMP/nd.out"; exit 1; }
grep -q "could not be made: refusing to run without the machine's lock" "$TMP/nd.out" || { echo "FAIL: no lock directory not said"; cat "$TMP/nd.out"; exit 1; }
mkdir -p "$TMP/badlock/slot-0.lock"
PWA_TEST_LOCK_DIR="$TMP/badlock" FAKE_PW_LOG="$TMP/nf.log" "$GEN" test > "$TMP/nf.out" 2>&1 && { echo "FAIL: a run with no lock file ran"; cat "$TMP/nf.out"; exit 1; }
grep -q "could not be opened: refusing to run without the machine's lock" "$TMP/nf.out" || { echo "FAIL: no lock file not said"; cat "$TMP/nf.out"; exit 1; }
[ ! -e "$TMP/nd.log" ] && [ ! -e "$TMP/nf.log" ] || { echo "FAIL: Playwright ran without its lock"; exit 1; }

# --timings with no directory (last, empty, or "--", which is the end of
# gen-pwa's options): refused with the usage line, nothing run
usage='gen-pwa test \[--timings <dir>\] \[--evidence <dir>\] \[-- <playwright args>\]'
run "$TMP/t1.log" --timings > "$TMP/t1.out" 2>&1 && { echo "FAIL: --timings last ran"; cat "$TMP/t1.out"; exit 1; }
grep -q "^gen-pwa test: --timings needs a directory: $usage\$" "$TMP/t1.out" || { echo "FAIL: --timings last not said"; cat "$TMP/t1.out"; exit 1; }
run "$TMP/t2.log" --timings "" > "$TMP/t2.out" 2>&1 && { echo "FAIL: --timings \"\" ran"; cat "$TMP/t2.out"; exit 1; }
grep -q "^gen-pwa test: --timings needs a directory: $usage\$" "$TMP/t2.out" || { echo "FAIL: --timings \"\" not said"; cat "$TMP/t2.out"; exit 1; }
run "$TMP/t3.log" --timings -- > "$TMP/t3.out" 2>&1 && { echo "FAIL: --timings -- ran"; cat "$TMP/t3.out"; exit 1; }
grep -q "^gen-pwa test: --timings needs a directory: $usage\$" "$TMP/t3.out" || { echo "FAIL: --timings -- not said"; cat "$TMP/t3.out"; exit 1; }
[ ! -e "$TMP/t1.log" ] && [ ! -e "$TMP/t2.log" ] && [ ! -e "$TMP/t3.log" ] || { echo "FAIL: Playwright ran with --timings and no directory"; exit 1; }
# --evidence <dir> (bats-lang/pwa#230): the same refusals, and the directory handed over
run "$TMP/e1.log" --evidence > "$TMP/e1.out" 2>&1 && { echo "FAIL: --evidence last ran"; cat "$TMP/e1.out"; exit 1; }
grep -q "^gen-pwa test: --evidence needs a directory: $usage\$" "$TMP/e1.out" || { echo "FAIL: --evidence last not said"; cat "$TMP/e1.out"; exit 1; }
run "$TMP/e2.log" --evidence -- > "$TMP/e2.out" 2>&1 && { echo "FAIL: --evidence -- ran"; cat "$TMP/e2.out"; exit 1; }
[ ! -e "$TMP/e1.log" ] && [ ! -e "$TMP/e2.log" ] || { echo "FAIL: Playwright ran with --evidence and no directory"; exit 1; }
run "$TMP/e3.log" --timings "$TMP/times" --evidence "$TMP/ev" -- --project x > "$TMP/e3.out" 2>&1 || { echo "FAIL: a run with --evidence"; cat "$TMP/e3.out"; exit 1; }
[ "$(grep -c "^evidence $TMP/ev\$" "$TMP/e3.log")" = 2 ] || { echo "FAIL: --evidence not handed over as PWA_TEST_EVIDENCE_DIR"; cat "$TMP/e3.log"; exit 1; }
[ "$(grep -c '^evidence pwa-evidence$' "$TMP/a.log")" = 2 ] || { echo "FAIL: the default evidence directory"; cat "$TMP/a.log"; exit 1; }
[ "$(grep -c '^options .*--require="' "$TMP/a.log")" = 2 ] && [ "$(grep -c '^source-left $' "$TMP/a.log")" = 2 ] || { echo "FAIL: the preload not named in NODE_OPTIONS, or its source left in the environment"; cat "$TMP/a.log"; exit 1; }
# a NODE_OPTIONS of the caller's is kept before ours
NODE_OPTIONS=--no-warnings run "$TMP/n.log" > "$TMP/n.out" 2>&1 || { echo "FAIL: a run with NODE_OPTIONS"; cat "$TMP/n.out"; exit 1; }
grep -q '^options .*--no-warnings .*--require="' "$TMP/n.log" || { echo "FAIL: the caller's NODE_OPTIONS lost"; cat "$TMP/n.log"; exit 1; }
# the preload is removed when the run ends
FAKE_PW_COPY_WATCH="$TMP/watch.cjs" run "$TMP/c.log" > "$TMP/c.out" 2>&1 || { echo "FAIL: a run that copies the preload"; cat "$TMP/c.out"; exit 1; }
f=$(grep -m1 '^watch-existed ' "$TMP/c.log"); f=${f#watch-existed }
[ -s "$TMP/watch.cjs" ] && [ ! -e "$f" ] || { echo "FAIL: the preload was not written, or is left after the run"; exit 1; }
# its tests (node --test): a page that does not answer, a test near its timeout, and each part failing
PWA_WATCH="$TMP/watch.cjs" node --test "$HERE/watch.test.mjs" > "$TMP/watch.out" 2>&1 || { echo "FAIL: the page watch's tests"; cat "$TMP/watch.out"; exit 1; }
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

# with two slots, a run that waits takes the slot that frees first, not
# slot 0 (bats-lang/pwa#84). Run A takes slot 0 and holds it for 60 s, run
# B takes slot 1 and holds it 12 s; run C starts while both are busy, says
# it waits, and must have finished (on slot 1, when B ends) while A still
# holds slot 0. A run that blocks on slot 0 finishes only after A ends.
slot_a= slot_b= slot_c=
slot_wait_fail() { kill "$slot_a" "$slot_b" "$slot_c" 2>/dev/null || true; echo "FAIL: $1"; cat "$TMP"/slot-*.out 2>/dev/null; exit 1; }
PWA_TEST_SLOTS=2 FAKE_PW_SLEEP=60 FAKE_PW_LOG="$TMP/slot-a.log" "$GEN" test > "$TMP/slot-a.out" 2>&1 &
slot_a=$!
i=0; while ! grep -q '^start' "$TMP/slot-a.log" 2>/dev/null; do i=$((i + 1)); [ $i -lt 100 ] || slot_wait_fail "slot run A did not start"; sleep 0.2; done
PWA_TEST_SLOTS=2 FAKE_PW_SLEEP=12 FAKE_PW_LOG="$TMP/slot-b.log" "$GEN" test > "$TMP/slot-b.out" 2>&1 &
slot_b=$!
i=0; while ! grep -q '^start' "$TMP/slot-b.log" 2>/dev/null; do i=$((i + 1)); [ $i -lt 100 ] || slot_wait_fail "slot run B did not start"; sleep 0.2; done
PWA_TEST_SLOTS=2 FAKE_PW_SLEEP=0 FAKE_PW_LOG="$TMP/slot-c.log" "$GEN" test > "$TMP/slot-c.out" 2>&1 &
slot_c=$!
i=0; while ! grep -q "waiting for another gen-pwa test" "$TMP/slot-c.out" 2>/dev/null; do i=$((i + 1)); [ $i -lt 100 ] || slot_wait_fail "slot run C did not wait"; sleep 0.2; done
if ! wait $slot_c; then slot_wait_fail "the waiting run C failed"; fi
grep -q '^end' "$TMP/slot-c.log" || slot_wait_fail "the waiting run C did not run"
if grep -q '^end' "$TMP/slot-a.log"; then slot_wait_fail "run C waited for slot 0: it finished only after run A, which held slot 0 for 60 s, had ended"; fi
wait $slot_a || slot_wait_fail "run A failed"
wait $slot_b || slot_wait_fail "run B failed"

# kill -TERM of gen-pwa mid-run: no server, no stand-in left
(FAKE_PW_SLEEP=30 FAKE_PW_LOG="$TMP/k.log" exec "$GEN" test > "$TMP/k.out" 2>&1) &
gen=$!
i=0; while ! grep -q '^fetched' "$TMP/k.log" 2>/dev/null; do i=$((i + 1)); [ $i -lt 100 ] || { echo "FAIL: the run did not start"; exit 1; }; sleep 0.2; done
kill -TERM $gen
wait $gen 2>/dev/null || true
i=0; while pgrep -f "$TMP/fake-pw" > /dev/null; do i=$((i + 1)); [ $i -lt 50 ] || { echo "FAIL: the stand-in outlived gen-pwa"; pgrep -af "$TMP/fake-pw"; exit 1; }; sleep 0.2; done
for p in $(ports "$TMP/k.log"); do closed "$p" || { echo "FAIL: port $p still served after kill -TERM"; exit 1; }; done
for k in $(sed -n 's/^keeper //p' "$TMP/k.log"); do
  s=$(ps -o stat= -p "$k" 2>/dev/null) || true
  case $s in ''|Z*) ;; *) echo "FAIL: keeper $k is left"; ps -o pid=,args= -p "$k"; exit 1 ;; esac
done

# a failing run: its status, and nothing left
if FAKE_PW_EXIT=1 run "$TMP/f.log" > "$TMP/f.out" 2>&1; then echo "FAIL: a failing run passed"; exit 1; fi
grep -q "tests failed" "$TMP/f.out" || { echo "FAIL: a failing run not said"; cat "$TMP/f.out"; exit 1; }
for p in $(ports "$TMP/f.log"); do closed "$p" || { echo "FAIL: port $p still served after a failing run"; exit 1; }; done

# Playwright's own exit statuses 70, 71 and 143 are the keeper's statuses
# for "could not serve", "could not start" and "stopped": they are a failed
# run, said as one, and the keeper's outcome is not said for them
for code in 70 71 143; do
  if FAKE_PW_EXIT=$code run "$TMP/x$code.log" > "$TMP/x.out" 2>&1; then echo "FAIL: a run that exits $code passed"; exit 1; fi
  grep -q "tests failed" "$TMP/x.out" && ! grep -q "could not be served\|could not be started\|stopped" "$TMP/x.out" || { echo "FAIL: Playwright's exit $code said as a keeper's outcome"; cat "$TMP/x.out"; exit 1; }
  for p in $(ports "$TMP/x$code.log"); do closed "$p" || { echo "FAIL: port $p still served after exit $code"; exit 1; }; done
done

# a keeper killed by a signal (SIGKILL: it cannot say how its run ended) is
# said as one whose exit status could not be read, not as a run that failed
# or as node that could not start
( st=0; FAKE_PW_SLEEP=30 run "$TMP/s.log" > "$TMP/s.out" 2>&1 || st=$?; echo $st > "$TMP/s.st.part"; mv "$TMP/s.st.part" "$TMP/s.st" ) &
i=0; while ! grep -q '^fetched' "$TMP/s.log" 2>/dev/null; do i=$((i + 1)); [ $i -lt 100 ] || { echo "FAIL: the signal run did not start"; exit 1; }; sleep 0.2; done
# the keepers are the parents of this test's stand-ins (logged as "keeper <pid>"):
# each is signalled once, when first logged; no other process is looked for
killed=" "
i=0; while [ ! -e "$TMP/s.st" ]; do
  i=$((i + 1)); [ $i -lt 200 ] || { echo "FAIL: the signal run did not end"; exit 1; }
  for k in $(sed -n 's/^keeper //p' "$TMP/s.log" 2>/dev/null); do
    case $killed in *" $k "*) ;; *) killed="$killed$k "; kill -KILL "$k" 2>/dev/null || true ;; esac
  done
  sleep 0.2
done
[ "$killed" != " " ] || { echo "FAIL: no keeper of the signal run was found to kill"; cat "$TMP/s.out"; exit 1; }
wait
[ "$(cat "$TMP/s.st")" -ne 0 ] || { echo "FAIL: a run whose keeper was killed passed"; exit 1; }
grep -q "its exit status could not be read (killed by a signal, or waitpid failed)" "$TMP/s.out" || { echo "FAIL: a killed keeper not said as unread"; cat "$TMP/s.out"; exit 1; }
grep -q "could not be started\|tests failed" "$TMP/s.out" && { echo "FAIL: a killed keeper said as another outcome"; cat "$TMP/s.out"; exit 1; }

# a Playwright older than 1.58 (the fake clock can set the time back), the
# floor itself, a later one with three digits (not string order), and a
# version that is none: only the first and the last are refused
version() { printf '{"name":"playwright-core","version":"%s"}\n' "$1" > "$P/node_modules/playwright-core/package.json"; }
for old in 1.57.9 1.9.0 1.58.0-alpha-1; do
  version "$old"
  rm -f "$TMP/v.log"
  if run "$TMP/v.log" > "$TMP/v.out" 2>&1; then echo "FAIL: ran with Playwright $old"; exit 1; fi
  grep -q "this project's Playwright is $old, older than 1.58" "$TMP/v.out" && grep -q "npm install --save-dev @playwright/test@^1.58" "$TMP/v.out" || { echo "FAIL: Playwright $old not said"; cat "$TMP/v.out"; exit 1; }
  [ ! -e "$TMP/v.log" ] || { echo "FAIL: Playwright ran with $old"; exit 1; }
done
for ok in 1.58.0 1.100.0 2.0.0; do
  version "$ok"
  run "$TMP/v-$ok.log" > "$TMP/v.out" 2>&1 || { echo "FAIL: refused Playwright $ok"; cat "$TMP/v.out"; exit 1; }
  if grep -q "older than 1.58" "$TMP/v.out"; then echo "FAIL: Playwright $ok said too old"; exit 1; fi
done
for bad in garbage 1.58 v1.58.0 ""; do
  version "$bad"
  rm -f "$TMP/v.log"
  if run "$TMP/v.log" > "$TMP/v.out" 2>&1; then echo "FAIL: ran with a version '$bad'"; exit 1; fi
  grep -q "cannot tell the version of this project's Playwright" "$TMP/v.out" || { echo "FAIL: version '$bad' not said"; cat "$TMP/v.out"; exit 1; }
  [ ! -e "$TMP/v.log" ] || { echo "FAIL: Playwright ran with a version '$bad'"; exit 1; }
done
version 1.58.2

# browsers older than Playwright expects, then none: said, nothing run
browsers_json 1300
if run "$TMP/o.log" > "$TMP/o.out" 2>&1; then echo "FAIL: ran with an older browser"; exit 1; fi
grep -q "older than this Playwright expects" "$TMP/o.out" && grep -q "chromium_headless_shell-1300" "$TMP/o.out" && grep -q "1194" "$TMP/o.out" || { echo "FAIL: an older browser not said"; cat "$TMP/o.out"; exit 1; }
[ ! -e "$TMP/o.log" ] || { echo "FAIL: Playwright ran with an older browser"; exit 1; }
rm -rf "$TMP/browsers/chromium_headless_shell-1194"
if run "$TMP/m.log" > "$TMP/m.out" 2>&1; then echo "FAIL: ran with no browser"; exit 1; fi
grep -q "is not installed" "$TMP/m.out" || { echo "FAIL: a missing browser not said"; cat "$TMP/m.out"; exit 1; }
# the scope of the check is said where it refuses (bats-lang/pwa#84, bullet 4): the headless shell, and what it does not check
grep -q "the headless Chromium this Playwright expects is not installed" "$TMP/m.out" && grep -q "covers the headless shell only" "$TMP/m.out" && grep -qF "a headed run's Chromium (chromium-<revision>)" "$TMP/m.out" || { echo "FAIL: the scope of the browser check not said"; cat "$TMP/m.out"; exit 1; }
# a headed run's Chromium is not checked, so the headless shell alone passes: Playwright runs, nothing is refused
browsers_json 1194
mkdir -p "$TMP/browsers/chromium_headless_shell-1194"
rm -f "$TMP/hd.log"
run "$TMP/hd.log" > "$TMP/hd.out" 2>&1 || { echo "FAIL: the headless shell alone was refused"; cat "$TMP/hd.out"; exit 1; }
[ -e "$TMP/hd.log" ] || { echo "FAIL: Playwright did not run with the headless shell alone"; exit 1; }
echo "test-command: ok"

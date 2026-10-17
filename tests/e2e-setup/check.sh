#!/bin/bash
# The e2e-setup action's scripts (.github/actions/e2e-setup), run by hand
# as its steps run them. Checked: npm ci retried when the connection drops
# (a fake npm; then the real npm against a registry that resets the first
# requests, once inside npm's own retries and once past them), not retried
# for a failure that is not the network's, a lock that does not match
# package.json or is missing fails, the Playwright minimum, the browsers'
# key changing with the Playwright version and not with the app, and the
# browsers install retried. The action's YAML (setup-node, the cache) can
# only run in a workflow: the job of check.yml that uses it is that test.
# usage: tests/e2e-setup/check.sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ACT=$(cd "$HERE/../../.github/actions/e2e-setup" && pwd)
TMP=$(mktemp -d)
STUB_PID=
cleanup() { [ -z "$STUB_PID" ] || kill "$STUB_PID" 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT
fail() { echo "FAIL: $1"; shift; for f in "$@"; do echo "--- $f"; cat "$f"; done; exit 1; }
export E2E_PAUSE_S=0 E2E_NPM_RETRY_MIN_MS=50 E2E_NPM_RETRY_MAX_MS=200

# --- a fake npm: fails N times with a given message, then succeeds
mkdir -p "$TMP/bin" "$TMP/p1"
cat > "$TMP/bin/npm" <<'FAKE'
#!/bin/sh
n=$(cat "$FAKE_COUNT" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "$FAKE_COUNT"
echo "args: $*" >> "$FAKE_COUNT.args"
if [ "$n" -le "${FAKE_FAILS:-0}" ]; then echo "$FAKE_MESSAGE" >&2; exit 1; fi
exit 0
FAKE
chmod +x "$TMP/bin/npm"
echo '{"name":"p"}' > "$TMP/p1/package.json"; echo '{}' > "$TMP/p1/package-lock.json"
fake() { # <fails> <message> -> runs npm-ci.sh in p1
  rm -f "$TMP/count" "$TMP/count.args"
  (cd "$TMP/p1" && PATH="$TMP/bin:$PATH" FAKE_COUNT="$TMP/count" FAKE_FAILS=$1 FAKE_MESSAGE=$2 "$ACT/npm-ci.sh") > "$TMP/out" 2>&1
}
ECONN='npm error code ECONNRESET
npm error network read ECONNRESET'

fake 2 "$ECONN" || fail "two dropped connections were not retried" "$TMP/out"
[ "$(cat "$TMP/count")" = 3 ] || fail "npm ran $(cat "$TMP/count") times, not 3"
grep -q '^args: ci --no-audit --no-fund --fetch-retries=5 --fetch-retry-mintimeout=50 --fetch-retry-maxtimeout=200$' "$TMP/count.args" || fail "npm's arguments" "$TMP/count.args"
if fake 3 "$ECONN"; then fail "three dropped connections passed" "$TMP/out"; fi
grep -q 'failed 3 times on a download' "$TMP/out" || fail "the message of exhausted tries" "$TMP/out"
[ "$(cat "$TMP/count")" = 3 ] || fail "tries past 3"
if fake 1 'npm error code EUSAGE
npm error `npm ci` can only install packages when your package.json and package-lock.json are in sync'; then fail "a lock out of sync passed" "$TMP/out"; fi
[ "$(cat "$TMP/count")" = 1 ] || fail "a failure that is not the network's was retried"
grep -q 'not from the network' "$TMP/out" || fail "the message of a failure not the network's" "$TMP/out"
# the registry says 503: also retried
fake 1 'npm error code E503' || fail "E503 not retried" "$TMP/out"

# --- no lock, no package.json
mkdir "$TMP/p2"; echo '{}' > "$TMP/p2/package.json"
(cd "$TMP/p2" && "$ACT/npm-ci.sh") > "$TMP/out" 2>&1 && fail "no lock passed" "$TMP/out"
grep -q 'no package-lock.json' "$TMP/out" || fail "the message of no lock" "$TMP/out"

# --- the real npm against a registry that resets connections
if command -v npm >/dev/null && command -v node >/dev/null; then
  mkdir -p "$TMP/tiny" && echo '{"name":"tiny","version":"1.0.0"}' > "$TMP/tiny/package.json"
  (cd "$TMP/tiny" && npm pack --silent --pack-destination "$TMP" >/dev/null)
  node "$HERE/registry-stub.js" "$TMP/tiny-1.0.0.tgz" > "$TMP/port" &
  STUB_PID=$!
  for _ in $(seq 50); do [ -s "$TMP/port" ] && break; sleep 0.1; done
  PORT=$(cat "$TMP/port")
  INTEG=sha512-$(openssl dgst -sha512 -binary "$TMP/tiny-1.0.0.tgz" | base64 -w0)
  real() { # <resets> <dir> -> npm-ci.sh against the stub, in a fresh project
    rm -rf "$2"; mkdir -p "$2"
    echo '{"name":"proj","version":"1.0.0","dependencies":{"tiny":"1.0.0"}}' > "$2/package.json"
    cat > "$2/package-lock.json" <<LOCK
{"name":"proj","version":"1.0.0","lockfileVersion":3,"requires":true,"packages":{"":{"name":"proj","version":"1.0.0","dependencies":{"tiny":"1.0.0"}},"node_modules/tiny":{"version":"1.0.0","resolved":"http://127.0.0.1:$PORT/tiny-1.0.0.tgz","integrity":"$INTEG"}}}
LOCK
    curl -s "http://127.0.0.1:$PORT/__reset/$1" >/dev/null
    (cd "$2" && npm_config_cache="$TMP/npmcache-$1" "$ACT/npm-ci.sh") > "$TMP/out" 2>&1
  }
  # 3 resets: inside npm's own 5 retries, one npm ci
  real 3 "$TMP/r1" || fail "3 resets (npm's own retries)" "$TMP/out"
  [ -f "$TMP/r1/node_modules/tiny/package.json" ] || fail "tiny not installed"
  [ "$(curl -s "http://127.0.0.1:$PORT/__count")" = 4 ] || fail "requests seen: $(curl -s "http://127.0.0.1:$PORT/__count"), not 4"
  # 8 resets: npm gives up after 6 requests, the second npm ci succeeds
  real 8 "$TMP/r2" || fail "8 resets (past npm's retries)" "$TMP/out"
  [ -f "$TMP/r2/node_modules/tiny/package.json" ] || fail "tiny not installed after 8 resets"
  grep -q 'the download failed (try 1 of 3)' "$TMP/out" || fail "the warning of the whole install again" "$TMP/out"
  # resets for ever: fails with the clear message
  real 1000 "$TMP/r3" && fail "endless resets passed" "$TMP/out"
  grep -q 'failed 3 times on a download' "$TMP/out" || fail "the message of endless resets" "$TMP/out"
  # a lock that does not match package.json: fails at once, one try
  real 0 "$TMP/r4" || fail "the control install" "$TMP/out"
  echo '{"name":"proj","version":"1.0.0","dependencies":{"tiny":"2.0.0"}}' > "$TMP/r4/package.json"
  rm -rf "$TMP/r4/node_modules"
  (cd "$TMP/r4" && npm_config_cache="$TMP/npmcache-0" "$ACT/npm-ci.sh") > "$TMP/out" 2>&1 && fail "a lock out of sync passed" "$TMP/out"
  grep -q 'not from the network' "$TMP/out" || fail "an out-of-sync lock was retried" "$TMP/out"
  grep -q "npm error code E" "$TMP/out" || fail "npm says no code for the mismatch" "$TMP/out"
else
  echo "SKIP: the real npm against a faulting registry (no node or npm)"
fi

# --- the Playwright version: the minimum and the browsers' key
pw() { # <dir> <version>
  mkdir -p "$1/node_modules/playwright-core"
  echo "{\"name\":\"playwright-core\",\"version\":\"$2\"}" > "$1/node_modules/playwright-core/package.json"
}
ver() { # <dir> <minimum> -> version.sh, outputs in <dir>/gh-out
  rm -f "$1/gh-out" "$1/gh-env"
  (cd "$1" && PLAYWRIGHT_MINIMUM=$2 BROWSERS_PATH=/tmp/br KEY_PREFIX=pb-Linux-X64- GITHUB_OUTPUT="$1/gh-out" GITHUB_ENV="$1/gh-env" "$ACT/playwright-version.sh") > "$TMP/out" 2>&1
}
mkdir "$TMP/a" "$TMP/b" "$TMP/c"
pw "$TMP/a" 1.58.2; pw "$TMP/b" 1.58.2; pw "$TMP/c" 1.57.0
echo 'console.log("app a")' > "$TMP/a/app.js"; echo 'console.log("app b, other")' > "$TMP/b/app.js"
ver "$TMP/a" 1.58 || fail "1.58.2 against 1.58" "$TMP/out"
ver "$TMP/b" 1.58 || fail "1.58.2 against 1.58 (b)" "$TMP/out"
cmp -s "$TMP/a/gh-out" "$TMP/b/gh-out" || fail "the key changed with the app" "$TMP/a/gh-out" "$TMP/b/gh-out"
grep -q '^browsers-key=pb-Linux-X64-1.58.2$' "$TMP/a/gh-out" || fail "the key" "$TMP/a/gh-out"
grep -q '^PLAYWRIGHT_BROWSERS_PATH=/tmp/br$' "$TMP/a/gh-env" || fail "the env" "$TMP/a/gh-env"
ver "$TMP/c" "" || fail "no minimum" "$TMP/out"
grep -q '^browsers-key=pb-Linux-X64-1.57.0$' "$TMP/c/gh-out" || fail "the key moves with the version" "$TMP/c/gh-out"
ver "$TMP/c" 1.58 && fail "1.57.0 passed against 1.58" "$TMP/out"
grep -q 'installs Playwright 1.57.0, older than the 1.58' "$TMP/out" || fail "the message of a version too old" "$TMP/out"
pw "$TMP/c" 1.100.0; ver "$TMP/c" 1.58 || fail "1.100.0 (a numeric, not a text, order)" "$TMP/out"
pw "$TMP/c" 1.58.0; ver "$TMP/c" 1.58 || fail "1.58.0 against 1.58" "$TMP/out"
mkdir "$TMP/d"; ver "$TMP/d" 1.58 && fail "no playwright-core passed" "$TMP/out"
grep -q 'playwright-core is not there' "$TMP/out" || fail "the message of no Playwright" "$TMP/out"
ver "$TMP/a" 1.x && fail "a bad minimum passed" "$TMP/out"

# --- the browsers: installed into the directory, retried
mkdir -p "$TMP/e/node_modules/.bin"
cat > "$TMP/e/node_modules/.bin/playwright" <<'FAKE'
#!/bin/sh
n=$(cat "$FAKE_COUNT" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "$FAKE_COUNT"
echo "$* in $PLAYWRIGHT_BROWSERS_PATH" >> "$FAKE_COUNT.args"
if [ "$n" -le "${FAKE_FAILS:-0}" ]; then echo "Error: Download failed: server returned code 500 body" >&2; exit 1; fi
mkdir -p "$PLAYWRIGHT_BROWSERS_PATH/chromium_headless_shell-1"
FAKE
chmod +x "$TMP/e/node_modules/.bin/playwright"
rm -f "$TMP/count" "$TMP/count.args"
(cd "$TMP/e" && FAKE_COUNT="$TMP/count" FAKE_FAILS=2 PLAYWRIGHT_BROWSERS_PATH="$TMP/br/ms" "$ACT/browsers.sh") > "$TMP/out" 2>&1 || fail "the browsers install, 2 drops" "$TMP/out"
[ -d "$TMP/br/ms/chromium_headless_shell-1" ] || fail "no browsers directory"
[ "$(cat "$TMP/count")" = 3 ] || fail "the install ran $(cat "$TMP/count") times"
grep -q "^install chromium in $TMP/br/ms$" "$TMP/count.args" || fail "install's arguments" "$TMP/count.args"

echo "e2e-setup: all checks passed"

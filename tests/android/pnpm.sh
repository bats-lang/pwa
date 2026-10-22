#!/bin/sh
# The pnpm step of the Android build (bats-lang/pwa#158): fetch-pnpm.sh, which
# build-android.sh sources, run with the real corepack against a registry
# that mirrors the pnpm release (pnpm-registry.js). Checked: a first answer
# that comes after the downloader's 30 s timeout is retried and the build
# goes on; a registry that never answers fails after every try, naming the
# URL; the binary is checked against its pin (a changed file is refused and
# removed, not retried); a wrapper that is not the pinned one is refused, not
# retried. Needs Node with corepack 0.35 or later (pnpm 12's entry points)
# and the npm registry, from which it takes the release it mirrors.
#
# usage: tests/android/pnpm.sh <fetch-pnpm.sh>
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
WORK=$(mktemp -d)
REGISTRY_PID=
cleanup() { [ -z "$REGISTRY_PID" ] || kill "$REGISTRY_PID" 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT
fail() { echo "FAIL: $1"; shift; for f in "$@"; do echo "--- $f"; cat "$f"; done; exit 1; }

# the release this host takes, as the downloader names its package
TARGET=$(node -p "process.platform + '-' + process.arch")
PACKAGE=@pnpm/exe.$TARGET
if [ "$(uname -s)" = Linux ] && ldd --version 2>&1 | grep -qi musl; then
  echo "SKIP: a musl host takes another package than the one this test mirrors"; exit 0
fi
mkdir "$WORK/mirror"
(cd "$WORK/mirror"
 npm pack pnpm@12.9.1 --silent > /dev/null; mv pnpm-12.9.1.tgz wrapper.tgz
 npm pack "$PACKAGE@12.9.1" --silent > /dev/null; mv ./*exe."$TARGET"-12.9.1.tgz binary.tgz
 npm view pnpm@12.9.1 --json > wrapper.json
 npm view "$PACKAGE@12.9.1" --json > binary.json)

# the mirror and the env of corepack against it
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0 COREPACK_INTEGRITY_KEYS=0 PNPM_PAUSE_S=0
NO_PROXY=127.0.0.1 no_proxy=127.0.0.1
export NO_PROXY no_proxy
serve() { # <mode> -> starts the mirror, sets PORT and COREPACK_NPM_REGISTRY
  [ -z "$REGISTRY_PID" ] || kill "$REGISTRY_PID" 2>/dev/null || true
  node "$HERE/pnpm-registry.js" "$WORK/mirror" "$PACKAGE" "$1" > "$WORK/port" &
  REGISTRY_PID=$!
  for _ in $(seq 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
  PORT=$(cat "$WORK/port"); : > "$WORK/port"
  export COREPACK_NPM_REGISTRY=http://127.0.0.1:$PORT
}
run() { # <script> -> sources it, prints pnpm's version
  COREPACK_HOME="$WORK/home" sh -c '. "$1"; $pnpm --version' sh "$1" > "$WORK/out" 2>&1
}
requests() { curl -s --noproxy '*' "http://127.0.0.1:$PORT/__count"; }
BINARY() { echo "$WORK/home/v1/pnpm/12.9.1/pnpm-native"; }

# --- the first answer is later than the downloader waits: retried, built
rm -rf "$WORK/home"; serve late-once
run "$SCRIPT" || fail "a first answer past the timeout was not retried" "$WORK/out"
grep -q 'timed out after 30s' "$WORK/out" || fail "the first try did not time out" "$WORK/out"
grep -q "failed (try 1 of 3)" "$WORK/out" || fail "the retry was not said" "$WORK/out"
[ "$(tail -n 1 "$WORK/out")" = 12.9.1 ] || fail "pnpm did not run after the retry" "$WORK/out"
[ "$(requests)" = 2 ] || fail "the mirror saw $(requests) requests, not 2"
echo "ok: a late first answer is retried"

# --- a binary that is not the pinned one is refused, and removed
printf x >> "$(BINARY)"
if run "$SCRIPT"; then fail "a changed binary passed" "$WORK/out"; fi
grep -q 'not the pinned' "$WORK/out" || fail "the pin was not named" "$WORK/out"
[ ! -e "$(BINARY)" ] || fail "the refused binary was kept"
echo "ok: a changed binary is refused"

# --- every try fails: non-zero, the URL named, every try made
rm -rf "$WORK/home"; serve down
if run "$SCRIPT"; then fail "a registry that is down passed" "$WORK/out"; fi
grep -q "could not download pnpm from http://127.0.0.1:$PORT/$PACKAGE/12.9.1 in 3 tries" "$WORK/out" || fail "the message of every try failing" "$WORK/out"
[ "$(requests)" = 3 ] || fail "the mirror saw $(requests) requests, not 3"
echo "ok: every try failing is a failure naming the URL"

# --- a wrapper that is not the pinned one is refused at once
rm -rf "$WORK/home"; serve ok
sed 's/sha512\.06b0/sha512.06b1/' "$SCRIPT" > "$WORK/changed.sh"
if run "$WORK/changed.sh"; then fail "a wrapper that is not the pinned one passed" "$WORK/out"; fi
grep -q 'not from the network' "$WORK/out" || fail "a wrong wrapper was retried" "$WORK/out"
echo "ok: a wrapper that is not the pinned one is refused"

# --- and a clean run passes with no retry
rm -rf "$WORK/home"; serve ok
run "$SCRIPT" || fail "a clean run failed" "$WORK/out"
! grep -q 'failed (try' "$WORK/out" || fail "a clean run retried" "$WORK/out"
[ "$(tail -n 1 "$WORK/out")" = 12.9.1 ] || fail "pnpm did not run" "$WORK/out"
echo "ok: a clean run"

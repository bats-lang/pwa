#!/bin/bash
# The generated Android project installs its packages from a committed
# lock (bats-lang/pwa#131): build-android.sh, the one create_android
# wrote, refuses to run without a pnpm-lock.yaml beside it, installs with
# --frozen-lockfile, and so fails on a lock that does not match its
# package.json, before anything else of the build runs and without
# rewriting the lock. Checked with a stand-in corepack that records its
# arguments and ends the script (status 42) at the step after the install,
# `cap add android`, so reaching 42 means the install passed:
#   1. no lock: refused, corepack never called;
#   2. a lock: pnpm install --frozen-lockfile, then 42;
#   3. the real pnpm, on a project with a local dependency: the lock it
#      made passes (42); a package.json that gained a dependency fails
#      with the lock out of date, the lock byte for byte as it was.
# usage: tests/android-lock/check.sh <build-android.sh>
set -eu
# Hang guards, not budgets: no call below may wait for ever (a CI run once
# sat 3 h 53 min here), so each blocking one is bounded by `timeout`, with
# stdin closed. A bound is generous for the work (a pnpm download, an
# install of two local packages); passing it fails the check, with the
# output, and never passes it.
HANG_GUARD_S=300
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
[ $# = 1 ] || { echo "usage: $0 <build-android.sh>" >&2; exit 2; }
SCRIPT=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; shift; for f in "$@"; do echo "--- $f"; cat "$f"; done; exit 1; }

# corepack [pnpm@version] <args>: recorded; `exec cap ...` ends the script
# with 42; any other command is the real pnpm when STUB_REAL is set
mkdir -p "$TMP/bin"
cat > "$TMP/bin/corepack" <<'STUB'
#!/bin/sh
shift # pnpm@version
echo "pnpm $*" >> "$STUB_LOG"
case "$1" in
  exec) exit 42 ;;
  *) [ -z "${STUB_REAL:-}" ] || exec $STUB_REAL "$@" ;; # STUB_REAL names its program by absolute path: by name it would find this stand-in again, and exec itself forever
esac
STUB
chmod +x "$TMP/bin/corepack"

# fetch-pnpm.sh, which build-android.sh sources, is replaced by a stand-in
# that only names the pnpm (its download and checksums are tested by
# tests/android/pnpm.sh, bats-lang/pwa#158), so the log holds the install alone
project() { # <dir>: the script beside a package.json
  mkdir -p "$1"; cp "$SCRIPT" "$1/build-android.sh"
  echo 'pnpm="corepack pnpm@12.9.1"' > "$1/fetch-pnpm.sh"
}
run() { # <dir> -> status in $TMP/status, output in $TMP/out
  rm -f "$STUB_LOG"; : > "$STUB_LOG"
  set +e
  (cd "$1" && PATH="$TMP/bin:$PATH" timeout "$HANG_GUARD_S" sh ./build-android.sh <&-) > "$TMP/out" 2>&1
  echo $? > "$TMP/status"
  set -e
}
export STUB_LOG="$TMP/log"

# 1. no lock
project "$TMP/p1"; echo '{"name":"p","private":true}' > "$TMP/p1/package.json"
run "$TMP/p1"
[ "$(cat "$TMP/status")" = 1 ] || fail "no lock: status $(cat "$TMP/status"), not 1" "$TMP/out"
grep -q "no pnpm-lock.yaml" "$TMP/out" || fail "no lock: not said" "$TMP/out"
[ ! -s "$STUB_LOG" ] || fail "no lock: corepack was called" "$STUB_LOG"
[ ! -e "$TMP/p1/node_modules" ] || fail "no lock: something was installed"

# 2. a lock: the install is frozen
project "$TMP/p2"; echo '{"name":"p","private":true}' > "$TMP/p2/package.json"
echo "lockfileVersion: '9.0'" > "$TMP/p2/pnpm-lock.yaml"
run "$TMP/p2"
[ "$(cat "$TMP/status")" = 42 ] || fail "lock: status $(cat "$TMP/status"), not 42" "$TMP/out"
grep -qx "pnpm install --frozen-lockfile" "$STUB_LOG" || fail "lock: install is not frozen" "$STUB_LOG"
[ "$(grep -c '^pnpm install' "$STUB_LOG")" = 1 ] || fail "lock: installed more than once" "$STUB_LOG"

# 3. the real pnpm
# the real program by absolute path (see the stand-in's STUB_REAL)
if command -v pnpm > /dev/null; then REAL=$(command -v pnpm)
elif command -v corepack > /dev/null && timeout "$HANG_GUARD_S" "$(command -v corepack)" pnpm@12.9.1 --version > /dev/null 2>&1 <&-; then REAL="$(command -v corepack) pnpm@12.9.1"
else REAL=; fi
if [ -z "$REAL" ]; then
  [ -z "${CI:-}" ] || fail "no pnpm in CI"
  echo "SKIP: the real pnpm (none found)"
else
  P="$TMP/p3"; project "$P"; mkdir -p "$P/dep"
  echo '{"name":"dep","version":"1.0.0"}' > "$P/dep/package.json"
  echo '{"name":"other","version":"1.0.0"}' > "$TMP/other.json"
  mkdir -p "$P/other"; cp "$TMP/other.json" "$P/other/package.json"
  echo '{"name":"p","private":true,"dependencies":{"dep":"file:./dep"}}' > "$P/package.json"
  printf 'nodeLinker: hoisted\n' > "$P/pnpm-workspace.yaml"
  (cd "$P" && timeout "$HANG_GUARD_S" $REAL install --lockfile-only > "$TMP/lock.out" 2>&1 <&-) || fail "the real pnpm made no lock" "$TMP/lock.out"
  [ -f "$P/pnpm-lock.yaml" ] || fail "no lock written"
  STUB_REAL="$REAL" run "$P"
  [ "$(cat "$TMP/status")" = 42 ] || fail "real: a matching lock failed (status $(cat "$TMP/status"))" "$TMP/out"
  cp "$P/pnpm-lock.yaml" "$TMP/lock.before"
  echo '{"name":"p","private":true,"dependencies":{"dep":"file:./dep","other":"file:./other"}}' > "$P/package.json"
  STUB_REAL="$REAL" run "$P"
  [ "$(cat "$TMP/status")" != 0 ] && [ "$(cat "$TMP/status")" != 42 ] || fail "real: a lock that does not match passed (status $(cat "$TMP/status"))" "$TMP/out"
  grep -q "OUTDATED_LOCKFILE\|frozen-lockfile" "$TMP/out" || fail "real: failed, but not for the lock" "$TMP/out"
  cmp -s "$P/pnpm-lock.yaml" "$TMP/lock.before" || fail "real: the lock was rewritten"
fi
echo "ok: the generated install is frozen to the committed lock"

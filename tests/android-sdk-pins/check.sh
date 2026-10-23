#!/bin/sh
# android-sdk-pins (bats-lang/pwa#137) against small packages and a stand-in
# for Google's download server: the pinned download installed, a package
# already as pinned left alone, a download that is not the pinned one refused
# (and the package that was there kept), a download cut short tried again, a
# download that cannot be had, and a pins file that is not usable.
# Shell, since it drives a built binary against files and a local server
# (tests/android/pnpm.sh is the precedent); the tool it tests is bats.
#
# usage: tests/android-sdk-pins/check.sh <android-sdk-pins binary>
set -eu
BIN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
SERVER=
cleanup() { [ -z "$SERVER" ] || kill "$SERVER" 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT
fail() { echo "FAIL: $1"; exit 1; }

export ANDROID_SDK_PINS_PAUSE_S=0

# a package: tools.zip holds tools/bin/run and tools/NOTICE
mkdir "$TMP/served"
python3 -I - "$TMP/served/tools.zip" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("tools/NOTICE", "notice\n")
    z.writestr("tools/bin/run", "run\n")
PY
GOOD=$(sha1sum "$TMP/served/tools.zip" | cut -c1-40)
BAD=0000000000000000000000000000000000000000
echo "<package>the pinned package.xml</package>" > "$TMP/tools.xml"

# the stand-in server cuts the first response of each file short
python3 -I "$HERE/server.py" "$TMP/served" "$TMP/port" 1 &
SERVER=$!
i=0
while [ ! -s "$TMP/port" ]; do
  i=$((i + 1)); [ "$i" -lt 100 ] || fail "the stand-in server did not start"
  sleep 0.1
done
URL="http://127.0.0.1:$(cat "$TMP/port")"

# run <name> <pins line> [ENV=value ...]: in a directory of its own, with
# pins.txt and tools.xml, against the SDK root $TMP/<name>-sdk
run() {
  name=$1; line=$2; shift 2
  mkdir -p "$TMP/$name"
  printf '# a comment\n\n%s\n' "$line" > "$TMP/$name/pins.txt"
  cp "$TMP/tools.xml" "$TMP/$name/tools.xml"
  mkdir -p "$TMP/$name-sdk"
  set +e
  (cd "$TMP/$name" && env "$@" "$BIN" install "$TMP/$name-sdk") > "$TMP/$name.out" 2>&1
  RC=$?
  set -e
  echo "== $name (exit $RC)"; cat "$TMP/$name.out"
}

# 1. the pinned download, the first response cut short, is installed
run good "tools $URL/tools.zip $GOOD . tools"
[ "$RC" = 0 ] || fail "good: exit $RC"
[ "$(cat "$TMP/good-sdk/tools/bin/run")" = run ] || fail "good: the package is not unpacked"
cmp "$TMP/tools.xml" "$TMP/good-sdk/tools/package.xml" || fail "good: package.xml is not the pinned one"
[ ! -e "$TMP/good-sdk/.android-sdk-pins/tools.zip" ] || fail "good: the zip is left behind"

# 2. as pinned already: nothing is downloaded (the URL has no server)
mkdir -p "$TMP/again-sdk/tools"; cp "$TMP/tools.xml" "$TMP/again-sdk/tools/package.xml"
run again "tools http://127.0.0.1:1/never.zip $GOOD . tools"
[ "$RC" = 0 ] || fail "already pinned: exit $RC"
grep -q 'already the pinned revision' "$TMP/again.out" || fail "already pinned: not said"
! grep -q curl "$TMP/again.out" || fail "already pinned: curl ran"

# 3. a download that is not the pinned one is refused, every try, and the
# package that was there stays
mkdir -p "$TMP/bad-sdk/tools"; echo old > "$TMP/bad-sdk/tools/OLD"
run bad "tools $URL/tools.zip $BAD . tools" ANDROID_SDK_PINS_ATTEMPTS=2
[ "$RC" = 1 ] || fail "bad: exit $RC"
[ "$(grep -c 'is not the pinned one' "$TMP/bad.out")" = 2 ] || fail "bad: not tried twice"
grep -q 'refused' "$TMP/bad.out" || fail "bad: not refused"
[ "$(cat "$TMP/bad-sdk/tools/OLD")" = old ] || fail "bad: the package that was there is changed"
[ ! -e "$TMP/bad-sdk/tools/bin" ] || fail "bad: something of the download is installed"
[ ! -e "$TMP/bad-sdk/.android-sdk-pins/tools.zip" ] || fail "bad: the zip is left behind"

# 4. a download that cannot be had (404)
run missing "tools $URL/nothing.zip $GOOD . tools" ANDROID_SDK_PINS_ATTEMPTS=1
[ "$RC" = 1 ] || fail "missing: exit $RC"
grep -q 'the download failed' "$TMP/missing.out" || fail "missing: not said"

# 5. a pins file that is not usable
run short "tools $URL/tools.zip $GOOD ."
[ "$RC" = 2 ] || fail "short line: exit $RC"
(cd "$TMP/good" && "$BIN" install) > "$TMP/usage.out" 2>&1 && fail "no root: exit 0"
grep -q usage "$TMP/usage.out" || fail "no root: no usage"
mkdir "$TMP/nopins"
(cd "$TMP/nopins" && "$BIN" install "$TMP/good-sdk") > "$TMP/nopins.out" 2>&1 && fail "no pins.txt: exit 0"
grep -q 'cannot read pins.txt' "$TMP/nopins.out" || fail "no pins.txt: not said"

# 6. the committed pins: five words a line, a package.xml beside each, and
# the sha1 is 40 lower case hex digits
PINS="$(dirname "$HERE")/../tools/android-sdk-pins"
grep -v '^#' "$PINS/pins.txt" | while read -r name url sha1 into dir extra; do
  [ -n "$dir" ] && [ -z "$extra" ] || fail "pins.txt: $name is not five words"
  echo "$sha1" | grep -Eq '^[0-9a-f]{40}$' || fail "pins.txt: $name has no sha1"
  case $url in https://dl.google.com/android/repository/*.zip) ;; *) fail "pins.txt: $name is not from Google" ;; esac
  [ -f "$PINS/$name.xml" ] || fail "pins.txt: no $name.xml"
done

echo "android-sdk-pins: all passed"

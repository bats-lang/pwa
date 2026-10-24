#!/bin/bash
# The relock's Android SDK pins (bats-lang/pwa#185, area: android-relock): relock.sh against a
# fixture of Google's two repository XML files served from a directory (file:// URLs, the
# archives' Last-Modified set by touch), with the tool built by the caller. Shell, since it
# drives a shell script and a built binary against files, as tests/android-sdk-pins/repin.sh does.
#
# usage: tests/android-relock/check.sh <android-sdk-pins binary> [<repin binary of
#        repository-prototype's tools/repin: the pull request's table is rendered and read>]
set -eu
BIN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
REPIN=
if [ $# -ge 2 ]; then REPIN=$(cd "$(dirname "$2")" && pwd)/$(basename "$2"); fi
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
FIXTURES=$ROOT/tests/android-sdk-pins/repin
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# server <name> <feed set>: $TMP/<name>-server serves the set's two feeds and one file for each
# archive the feeds list, whose age in days (Last-Modified) is the table's, else 100
server() {
  dir=$TMP/$1-server
  mkdir -p "$dir/sys-img/android"
  cp "$FIXTURES/$2/repository2-1.xml" "$dir/"
  cp "$FIXTURES/$2/sys-img2-1.xml" "$dir/sys-img/android/"
  for entry in pt-r1:40 pl-r3:41 emu-r1:42 sys-r4:43 emu-r4:9 emu-r38:11 pt-r2:12 pl-r5:13 sys-r6:14; do
    name=${entry%%:*}.zip
    printf x > "$dir/$name"
    touch -d "$(( ${entry#*:} * 24 + 12 )) hours ago" "$dir/$name"
  done
  cat "$dir/repository2-1.xml" "$dir/sys-img/android/sys-img2-1.xml" | grep -o '<url>[^<]*</url>' \
    | while read -r line; do
        name=${line#<url>}; name=${name%</url>}
        [ -e "$dir/$name" ] || { printf x > "$dir/$name"; touch -d "2412 hours ago" "$dir/$name"; }
      done
}

# relock <name>: relock.sh in $TMP/<name>, a copy of the fixture pins and packages, against
# $TMP/<name>-server; its status, records and stderr are $TMP/<name>.status, .out and .err
relock() {
  mkdir -p "$TMP/$1"
  cp "$FIXTURES/pins.txt" "$FIXTURES"/*.xml "$TMP/$1/"
  : > "$TMP/$1.out"
  set +e
  ANDROID_SDK_PINS_BIN=$BIN ANDROID_SDK_FEEDS_URL=file://$TMP/$1-server \
    ANDROID_SDK_ARCHIVES_URL=file://$TMP/$1-server REPIN_RECORDS=$TMP/$1.out \
    sh "$ROOT/tools/android-sdk-pins/relock.sh" "$TMP/$1" 2> "$TMP/$1.err"
  echo $? > "$TMP/$1.status"
  set -e
  echo "== $1 (exit $(cat "$TMP/$1.status"))"
  cat "$TMP/$1.out" "$TMP/$1.err"
}
status_is() { [ "$(cat "$TMP/$1.status")" = "$2" ] || fail "$1: exit $(cat "$TMP/$1.status"), not $2"; }
unchanged() { name=$1; shift; for f in "$@"; do cmp "$FIXTURES/$f" "$TMP/$name/$f" || fail "$name: $f changed"; done; }
record() { local IFS=$'\t'; echo "$*"; }
PACKAGES="emulator.xml platform-tools.xml platforms-android-34.xml system-image.xml"

# 1. every pin current: the run does nothing (no file changed, four current records)
server current current
relock current
status_is current 0
unchanged current pins.txt $PACKAGES
{ record android-sdk platform-tools 37.0.1 37.0.1 40 current
  record android-sdk platforms-android-34 3 3 41 current
  record android-sdk emulator 37.2.12 37.2.12 42 current
  record android-sdk system-image 4 4 43 current; } > "$TMP/current.want"
cmp "$TMP/current.want" "$TMP/current.out" || fail "current: not four current records"
echo "ok: every pin current, nothing moved"

# 2. the emulator is older than the stable one: pins.txt moves it to that revision with the
# feed's SHA-1, emulator.xml is the new revision, the rest stays, the record names both
NEW_SHA=0123456789abcdef0123456789abcdef01234567
server newer newer
relock newer
status_is newer 0
# the fixture's pins name http://x.test/: the move keeps the pinned URL's directory
{ head -n 3 "$FIXTURES/pins.txt"
  echo "emulator http://x.test/emu-r4.zip $NEW_SHA . emulator"
  tail -n 1 "$FIXTURES/pins.txt"; } > "$TMP/newer.want"
cmp "$TMP/newer.want" "$TMP/newer/pins.txt" || fail "newer: pins.txt is not just the emulator moved to emu-r4 with the feed's SHA-1"
unchanged newer platform-tools.xml platforms-android-34.xml system-image.xml
grep -q '<major>37</major><minor>4</minor><micro>1</micro>' "$TMP/newer/emulator.xml" \
  || fail "newer: emulator.xml is not revision 37.4.1"
{ record android-sdk platform-tools 37.0.1 37.0.1 40 current
  record android-sdk platforms-android-34 3 3 41 current
  record android-sdk emulator 37.2.12 37.4.1 9 moved
  record android-sdk system-image 4 4 43 current; } > "$TMP/newer.want.out"
cmp "$TMP/newer.want.out" "$TMP/newer.out" || fail "newer: the records are not the move"
echo "ok: emulator 37.2.12 moved to 37.4.1"

# 3. the pull request's table, rendered by repository-prototype's tools/repin
if [ -n "$REPIN" ]; then
  "$REPIN" table "$TMP/newer.out" > "$TMP/newer.table"
  cat "$TMP/newer.table"
  grep -Fxq '| android-sdk | emulator | 37.2.12 | 37.4.1 | 9 days | moved |' "$TMP/newer.table" \
    || fail "table: the emulator's old and new revision are not in the row"
  "$REPIN" table "$TMP/current.out" > "$TMP/current.table"
  grep -Fq 'moved' "$TMP/current.table" && fail "table: a current run lists a move"
  echo "ok: the table names the old and the new revision"
fi

# 4. the newest archive gives no Last-Modified (not served): the run fails, nothing is written
server noage newer
rm "$TMP/noage-server/emu-r4.zip"
relock noage
[ "$(cat "$TMP/noage.status")" != 0 ] || fail "noage: the run passed with no age for the new archive"
grep -qF "emulator: the age file of the new archive cannot be read" "$TMP/noage.err" || fail "noage: stderr lacks the reason"
unchanged noage pins.txt emulator.xml
echo "ok: a missing age fails the run and moves nothing"

# 5. a feed that is not served: the run fails
server nofeed current
rm "$TMP/nofeed-server/repository2-1.xml"
relock nofeed
[ "$(cat "$TMP/nofeed.status")" != 0 ] || fail "nofeed: the run passed without a feed"
unchanged nofeed pins.txt $PACKAGES
echo "ok: a missing feed fails the run"

# 6. relock.yml calls relock.sh with the pins directory, as this test does
grep -Fxq '        sh tools/android-sdk-pins/relock.sh tools/android-sdk-pins' "$ROOT/.github/workflows/relock.yml" \
  || fail "relock.yml does not run the script with the pins directory"
echo "ok: relock.yml runs relock.sh"

#!/bin/bash
# android-sdk-pins repin (bats-lang/pwa#184, piece 1 of pwa#173): the pins move to the
# newest stable revision of Google's repository XML, against fixtures of the feeds in
# tests/android-sdk-pins/repin/ (shell, since it drives a built binary against files, as
# check.sh does; the tool it tests is bats).
#
# usage: tests/android-sdk-pins/repin.sh <android-sdk-pins binary>
set -eu
BIN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
HERE=$(cd "$(dirname "$0")" && pwd)
FIXTURES=$HERE/repin
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# The ages (whole days) the workflow writes beside the feeds, one file for each archive
write_ages() {
  for entry in pt-r1:40 pl-r3:41 emu-r1:42 sys-r4:43 emu-r4:9 emu-r38:11 pt-r2:12 \
               pl-r5:13 sys-r6:14; do
    echo "${entry#*:}" > "$1/${entry%%:*}.zip.age"
  done
}

# feeds <name> <feed set>: $TMP/<name>-feeds is a copy of the set with the ages
feeds() {
  mkdir "$TMP/$1-feeds"
  cp "$FIXTURES/$2"/*.xml "$TMP/$1-feeds/"
  write_ages "$TMP/$1-feeds"
}

# run_in <name> <directory> [argument...]: the tool in the directory; its status, stdout
# and stderr are $TMP/<name>.status, .out and .err
run_in() {
  name=$1; directory=$2; shift 2
  set +e
  (cd "$directory" && "$BIN" "$@") > "$TMP/$name.out" 2> "$TMP/$name.err"
  echo $? > "$TMP/$name.status"
  set -e
  echo "== $name (exit $(cat "$TMP/$name.status"))"
  cat "$TMP/$name.out" "$TMP/$name.err"
}

# repin <name>: in $TMP/<name>, a copy of the fixture pins and packages, with the feeds of
# $TMP/<name>-feeds
repin() {
  mkdir -p "$TMP/$1"
  cp "$FIXTURES/pins.txt" "$FIXTURES"/*.xml "$TMP/$1/"
  run_in "$1" "$TMP/$1" repin "$TMP/$1-feeds"
}

status_is() {
  [ "$(cat "$TMP/$1.status")" = "$2" ] || fail "$1: exit $(cat "$TMP/$1.status"), not $2"
}
said() { grep -qF -- "$2" "$TMP/$1.err" || fail "$1: stderr lacks: $2"; }
has() { grep -qF -- "$2" "$TMP/$1" || fail "$1 lacks: $2"; }
unchanged() { # <name> <file...>: the files are the fixture's, byte for byte
  name=$1; shift
  for file in "$@"; do
    cmp "$FIXTURES/$file" "$TMP/$name/$file" || fail "$name: $file changed"
  done
}
record() { # fields...: a record line, tab separated
  local IFS=$'\t'; echo "$*"
}
PACKAGES="emulator.xml platform-tools.xml platforms-android-34.xml system-image.xml"

# 1. every pin current: nothing is written, every record says current (with the age of
# the pinned archive)
feeds current current
repin current
status_is current 0
unchanged current pins.txt $PACKAGES
{ record android-sdk platform-tools 37.0.1 37.0.1 40 current
  record android-sdk platforms-android-34 3 3 41 current
  record android-sdk emulator 37.2.12 37.2.12 42 current
  record android-sdk system-image 4 4 43 current; } > "$TMP/current.want"
cmp "$TMP/current.want" "$TMP/current.out" || fail "current: not four current records"

# 2. newer revisions only on the dev channel, or in an obsolete package: nothing moves
feeds dev-only dev-only
repin dev-only
status_is dev-only 0
unchanged dev-only pins.txt $PACKAGES
cmp "$TMP/current.want" "$TMP/dev-only.out" || fail "dev-only: not four current records"

# 3. the emulator is older than the stable one (listed first, last, and with a newer dev
# one; the newest has a macosx archive and an aarch64 one before the linux x86_64 one):
# pins.txt moves it to the feed's URL and SHA-1, the other lines stay
NEW_SHA=0123456789abcdef0123456789abcdef01234567
OLD_REVISION=$'<revision>\n<major>37</major>\n<minor>2</minor>\n<micro>12</micro>\n</revision>'
NEW_REVISION='<revision><major>37</major><minor>4</minor><micro>1</micro></revision>'
for set in newer newer-last; do
  feeds $set $set
  repin $set
  status_is $set 0
  { head -n 3 "$FIXTURES/pins.txt"
    echo "emulator http://x.test/emu-r4.zip $NEW_SHA . emulator"
    tail -n 1 "$FIXTURES/pins.txt"; } > "$TMP/$set.want"
  cmp "$TMP/$set.want" "$TMP/$set/pins.txt" || fail "$set: pins.txt: not just the emulator moved"
  unchanged $set platform-tools.xml platforms-android-34.xml system-image.xml
  old_xml=$(cat "$FIXTURES/emulator.xml"; printf x); old_xml=${old_xml%x}
  want_xml=${old_xml/"$OLD_REVISION"/$NEW_REVISION}
  [ "$want_xml" != "$old_xml" ] || fail "$set: the fixture's revision text is not there"
  printf '%s' "$want_xml" > "$TMP/$set.want.xml"
  cmp "$TMP/$set.want.xml" "$TMP/$set/emulator.xml" || fail "$set: emulator.xml: not 37.4.1"
  { record android-sdk platform-tools 37.0.1 37.0.1 40 current
    record android-sdk platforms-android-34 3 3 41 current
    record android-sdk emulator 37.2.12 37.4.1 9 moved
    record android-sdk system-image 4 4 43 current; } > "$TMP/$set.want.out"
  cmp "$TMP/$set.want.out" "$TMP/$set.out" || fail "$set: the records are not the move"
done

# 4. the same run on what it wrote moves nothing more
mkdir "$TMP/again"
cp "$TMP/newer/pins.txt" "$TMP/newer"/*.xml "$TMP/again/"
run_in again "$TMP/again" repin "$TMP/newer-feeds"
status_is again 0
for file in pins.txt emulator.xml; do
  cmp "$TMP/newer/$file" "$TMP/again/$file" || fail "again: $file changed"
done
[ "$(grep -c 'current$' "$TMP/again.out")" = 4 ] || fail "again: not four current records"

# 5. every pin has a newer stable revision, the stable channel being channel-5 and the
# dev one channel-0: each line and package.xml moves, the display name from the feed
feeds all all-newer
repin all
status_is all 0
cat > "$TMP/all.want" <<'EOF'
# Fixture pins (tests/android-sdk-pins/repin.sh): name url sha1 unzip-into package-dir
platform-tools http://x.test/pt-r2.zip 6666666666666666666666666666666666666666 . platform-tools
platforms-android-34 http://x.test/pl-r5.zip 7777777777777777777777777777777777777777 platforms p/34
emulator http://x.test/emu-r38.zip 5555555555555555555555555555555555555555 . emulator
system-image http://x.test/sys-r6.zip ffffffffffffffffffffffffffffffffffffffff img img/x86_64
EOF
cmp "$TMP/all.want" "$TMP/all/pins.txt" || fail "all: pins.txt is not four moved lines"
has all/platform-tools.xml '<revision><major>37</major><minor>0</minor><micro>2</micro></revision>'
has all/emulator.xml '<revision><major>38</major><minor>0</minor><micro>2</micro></revision>'
has all/platforms-android-34.xml '<revision><major>5</major></revision>'
has all/platforms-android-34.xml '<display-name>Android SDK Platform 34-ext7</display-name>'
has all/platforms-android-34.xml '<extension-level>7</extension-level>'
has all/system-image.xml '<revision><major>6</major></revision>'
has all/system-image.xml '<dependencies>'
{ record android-sdk platform-tools 37.0.1 37.0.2 12 moved
  record android-sdk platforms-android-34 3 5 13 moved
  record android-sdk emulator 37.2.12 38.0.2 11 moved
  record android-sdk system-image 4 6 14 moved; } > "$TMP/all.want.out"
cmp "$TMP/all.want.out" "$TMP/all.out" || fail "all: the records are not four moves"

# 6. a feed that is not usable stops the run with status 1, naming the package, and
# pins.txt stays: a checksum that is not 40 characters, one with upper case digits, no
# archive for Linux, no stable channel, no age file for the new archive or the pinned one
broken() { # <name> <feed set> <text in the feed files> <replacement>
  feeds "$1" "$2"
  for file in "$TMP/$1-feeds"/*.xml; do
    text=$(cat "$file"; printf x); text=${text%x}
    printf '%s' "${text//"$3"/$4}" > "$file"
  done
}
broken short newer "$NEW_SHA" 0123456789
repin short; status_is short 1
said short "emulator: the feed's checksum is not 40 characters"
unchanged short pins.txt emulator.xml
broken upper newer "$NEW_SHA" 0123456789ABCDEF0123456789abcdef01234567
repin upper; status_is upper 1
said upper "emulator: the feed's checksum is not lower case hex"
unchanged upper pins.txt emulator.xml
broken solaris newer '<host-os>linux<' '<host-os>solaris<'
repin solaris; status_is solaris 1
said solaris "emulator: the newest stable revision has no archive for Linux on x86_64"
unchanged solaris pins.txt emulator.xml
broken steady newer '>stable<' '>steady<'
repin steady; status_is steady 1
said steady "platform-tools: no stable revision of the package is in the feeds"
unchanged steady pins.txt
feeds noage newer; rm "$TMP/noage-feeds/emu-r4.zip.age"
repin noage; status_is noage 1
said noage "emulator: the age file of the new archive cannot be read"
unchanged noage pins.txt emulator.xml
feeds nopinnedage current; rm "$TMP/nopinnedage-feeds/pt-r1.zip.age"
repin nopinnedage; status_is nopinnedage 1
said nopinnedage "platform-tools: the age file of the pinned archive cannot be read"
feeds badage current; echo 'many days' > "$TMP/badage-feeds/pt-r1.zip.age"
repin badage; status_is badage 1
said badage "platform-tools: the age file of the pinned archive cannot be read"

# 7. the command line and the files
feeds nofeeds current
rm "$TMP/nofeeds-feeds/sys-img2-1.xml"
repin nofeeds; status_is nofeeds 1
said nofeeds "sys-img2-1.xml: unreadable"
mkdir "$TMP/noxml"; cp "$FIXTURES/pins.txt" "$TMP/noxml/"
run_in noxml "$TMP/noxml" repin "$TMP/current-feeds"
status_is noxml 1
said noxml "platform-tools.xml cannot be read"
mkdir "$TMP/nopins"
run_in nopins "$TMP/nopins" repin "$TMP/current-feeds"
status_is nopins 2
said nopins "cannot read pins.txt"
mkdir "$TMP/threewords"; printf 'tools http://x.test/t.zip abc\n' > "$TMP/threewords/pins.txt"
run_in threewords "$TMP/threewords" repin "$TMP/current-feeds"
status_is threewords 2
run_in usage "$TMP/current" repin
status_is usage 2
said usage "usage: android-sdk-pins repin <feed-directory>"

echo "android-sdk-pins repin: all passed"

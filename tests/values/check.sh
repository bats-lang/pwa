#!/bin/sh
# gen-pwa values (bats-lang/pwa#244): the JSON file is quire's sync-clients.json byte for
# byte, and each refusal says what and why, exits 1 and writes no file.
# The reference is quire's own scripts/sync-clients.sh and sync-clients.env, copied unchanged
# from bats-lang/quire at 619e898 (tests/values/); non-bats code of ours is this driver of the
# built binary (the avenue exhausted: bats has no process-level test of a built program here,
# as tests/static-pages/check.sh).
# usage: tests/values/check.sh <gen-pwa binary>
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
GEN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'chmod -R u+w "$TMP"; rm -rf "$TMP"' EXIT
cd "$TMP"
mkdir -p dist/pwa
fail() { echo "FAIL: $1"; cat out.txt 2>/dev/null; exit 1; }
GOOGLE='[0-9]+-[0-9a-z]+\.apps\.googleusercontent\.com'
DROPBOX='[a-z0-9]{8,64}'
SPECS="GOOGLE_WEB_CLIENT_ID:googleWebClient:$GOOGLE DROPBOX_CLIENT_ID:dropboxClient:$DROPBOX"
# refused(what, message part, args...): exit 1, said, and dist/pwa/v.json not made
refused() {
  what=$1; part=$2; shift 2
  [ -d dist/pwa/v.json ] || rm -f dist/pwa/v.json
  if "$GEN" values "$@" > out.txt 2>&1; then fail "$what: exit 0"; fi
  grep -q -- "$part" out.txt || fail "$what: not said ($part)"
  [ -d dist/pwa/v.json ] || [ ! -e dist/pwa/v.json ] || fail "$what: a file was made"
}
# 1. quire's file, byte for byte
mkdir ref; cp "$HERE/sync-clients.sh" "$HERE/sync-clients.env" ref/
sh ref/sync-clients.sh dist/pwa > /dev/null
mv dist/pwa/sync-clients.json ref.json
# shellcheck disable=SC2086
"$GEN" values "$HERE/sync-clients.env" sync-clients.json $SPECS > out.txt 2>&1 || fail "the values"
cmp ref.json dist/pwa/sync-clients.json || fail "sync-clients.json differs from the script's"
echo "sync-clients.json: $(cat dist/pwa/sync-clients.json)"
# 2. forms: counts, classes, escapes and backtracking
printf 'A=bca\nB=ab-12\nC=x.y\nD=\n# E=hidden\n' > e.env
ok() {
  what=$1; want=$2; shift 2
  rm -f dist/pwa/v.json
  "$GEN" values e.env v.json "$@" > out.txt 2>&1 || fail "$what: refused"
  [ "$(cat dist/pwa/v.json)" = "$want" ] || fail "$what: got $(cat dist/pwa/v.json)"
}
ok "backtracking" '{"a": "bca"}' 'A:a:[a-z]+a'
ok "two values" '{"a": "bca", "b": "ab-12"}' 'A:a:[a-z]{3}' 'B:b:[a-z]{2}\-[0-9]{1,2}'
ok "class with a dash and a range" '{"b": "ab-12"}' 'B:b:[a-z\-0-9]+'
ok "escaped dot" '{"c": "x.y"}' 'C:c:x\.y'
ok "empty value" '{"d": ""}' 'D:d:[a-z]{0,3}'
refused "a dot is not any character" "not of the form" e.env v.json 'C:c:x_y'
refused "too few" "not of the form" e.env v.json 'A:a:[a-z]{4,5}'
refused "too many" "not of the form" e.env v.json 'A:a:[a-z]{1,2}'
refused "trailing text" "not of the form" e.env v.json 'A:a:[a-z]{2}'
refused "a comment line is no value" "no line NAME=value" e.env v.json 'E:e:[a-z]+'
# 3. refusals
refused "missing name" "NOPE: no line NAME=value in e.env" e.env v.json 'NOPE:nope:[a-z]+'
refused "malformed value, the first of two" "A in e.env: the value is not of the form" e.env v.json 'A:a:[0-9]+' 'B:b:.*'
printf 'Q=a"b\nR=a\\b\nS=tab\there\nT=caf\303\251\n' > bad.env
for n in Q R S T; do
  refused "plain value $n" "$n in bad.env: the value has a character" bad.env v.json "$n:k:[^ ]+"
done
printf 'A=1\nA=2\n' > twice.env
refused "repeated name" "A: more than one line" twice.env v.json 'A:a:[0-9]'
refused "unreadable env file, missing" "nowhere.env: .*not found" nowhere.env v.json 'A:a:[a-z]'
mkdir envdir
refused "unreadable env file, a directory" "envdir: .*directory" envdir v.json 'A:a:[a-z]'
if [ "$(id -u)" != 0 ]; then
  cp e.env locked.env; chmod 000 locked.env
  refused "unreadable env file, permission" "locked.env: .*permission denied" locked.env v.json 'A:a:[a-z]'
fi
head -c 600000 /dev/zero | tr '\0' 'a' > big.env
refused "env file too large" "too large for an env file" big.env v.json 'A:a:[a-z]'
# specs
refused "no colon" "not NAME:KEY:FORM" e.env v.json 'A'
refused "one colon" "not NAME:KEY:FORM" e.env v.json 'A:a'
refused "empty name" "NAME must be" e.env v.json ':a:[a-z]'
refused "bad name" "NAME must be" e.env v.json 'A-B:a:[a-z]'
refused "empty key" "KEY must be" e.env v.json 'A::[a-z]'
refused "key with a quote" "KEY must be" e.env v.json 'A:a"b:[a-z]'
refused "empty form" "FORM is empty" e.env v.json 'A:a:'
for f in '[a-z' '[]' '[a-z]{' '[a-z]{2' '[a-z]{3,2}' '[a-z]{,2}' '+' 'a\' ']' '}' 'a?' 'a*' '[a-z]{123456789}'; do
  refused "bad form $f" "FORM is not a form" e.env v.json "A:a:$f"
done
# arguments and the output name
refused "no arguments" "usage"
refused "one argument" "usage" e.env
refused "two arguments" "usage" e.env v.json
for n in "" . .. ../x a/b /abs; do
  refused "output name '$n'" "OUTFILE must be one name" e.env "$n" 'A:a:[a-z]+'
done
[ ! -e dist/x ] || fail "an output name left dist/pwa"
# a refusal leaves an existing file as it was
printf 'keep\n' > dist/pwa/v.json
if "$GEN" values e.env v.json 'NOPE:nope:x' > out.txt 2>&1; then fail "refused value, exit 0"; fi
[ "$(cat dist/pwa/v.json)" = keep ] || fail "a refusal touched an existing file"
# a second run replaces the file, as the script's redirection does
"$GEN" values e.env v.json 'D:d:[a-z]{0,3}' > out.txt 2>&1 || fail "second run"
[ "$(cat dist/pwa/v.json)" = '{"d": ""}' ] || fail "the file was not replaced"
# the JSON is larger than the buffer: the same 300000 byte value under two keys
head -c 300000 /dev/zero | tr '\0' 'a' > half.env
{ printf 'A='; cat half.env; printf '\n'; } > large.env
refused "output too large" "524288 bytes or more" large.env v.json 'A:one:[a-z]+' 'A:two:[a-z]+'
"$GEN" values large.env v.json 'A:one:[a-z]+' > out.txt 2>&1 || fail "a 300000 byte value"
[ "$(wc -c < dist/pwa/v.json)" = 300012 ] || fail "the size of the large file"
# 4. a write that fails
rm -f dist/pwa/v.json; mkdir dist/pwa/v.json
refused "write failed, a directory" "dist/pwa/v.json: .*directory" e.env v.json 'D:d:[a-z]{0,3}'
rmdir dist/pwa/v.json
if [ "$(id -u)" != 0 ]; then
  chmod 555 dist/pwa
  refused "write failed, read-only" "dist/pwa/v.json: .*permission denied" e.env v.json 'D:d:[a-z]{0,3}'
  chmod 755 dist/pwa
fi
rm -rf dist
refused "write failed, no dist/pwa" "dist/pwa/v.json: .*not found" e.env v.json 'D:d:[a-z]{0,3}'
echo "gen-pwa values: ok"

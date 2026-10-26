#!/bin/sh
# gen-pwa pages (bats-lang/pwa#243): the tree is copied byte for byte, and each
# outcome is said with its reason and exits 1.
# usage: tests/static-pages/check.sh <gen-pwa binary>
set -eu
GEN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'chmod -R u+w "$TMP"; rm -rf "$TMP"' EXIT
cd "$TMP"
mkdir -p dist/pwa src/a/b src/empty
printf 'index\n' > src/index.html
printf '\000\001\377binary' > src/a/b/blob.bin
printf '#!/bin/sh\n' > src/a/run.sh; chmod 755 src/a/run.sh
: > src/zero
fail() { echo "FAIL: $1"; cat out.txt 2>/dev/null; exit 1; }
# refused(<what> <message part> <args...>): exit 1, said
refused() {
  what=$1; part=$2; shift 2
  if "$GEN" pages "$@" > out.txt 2>&1; then fail "$what: exit 0"; fi
  grep -q -- "$part" out.txt || fail "$what: not said ($part)"
}
"$GEN" pages src home > out.txt 2>&1 || fail "a copy"
diff -r src dist/pwa/home || fail "the trees differ"
[ -x dist/pwa/home/a/run.sh ] || fail "the mode of a file"
[ -d dist/pwa/home/empty ] || fail "an empty directory"
# a destination that exists is refused and left as it was
printf 'keep\n' > dist/pwa/home/index.html
refused "destination exists" "the destination exists" src home
[ "$(cat dist/pwa/home/index.html)" = keep ] || fail "the destination was touched"
# a missing source, a file as source: refused, nothing made
refused "missing source" "not a readable directory" nowhere other
refused "file as source" "not a readable directory" src/index.html other
[ ! -e dist/pwa/other ] || fail "a refused source left a destination"
# a name that leaves dist/pwa
for n in "" . .. ../x a/b /abs; do
  refused "name '$n'" "NAME must be one name" src "$n"
done
[ ! -e dist/x ] || fail "a name left dist/pwa"
# arguments
refused "no arguments" "usage" 
refused "one argument" "usage" src
refused "three arguments" "usage" src a b
# a write that fails: dist/pwa is read-only (skipped for root, who may write)
if [ "$(id -u)" != 0 ]; then
  rm -rf dist; mkdir -p dist/pwa; chmod 555 dist/pwa
  refused "write failed" "Permission denied" src home
  chmod 755 dist/pwa
fi
# a write that fails for any user: dist/pwa is missing
rm -rf dist
refused "write failed, no dist/pwa" "dist/pwa/home: .*not found" src home
mkdir -p dist/pwa
# a read that fails for any user: a link to nothing inside the source
mkdir -p dangling; ln -s nowhere dangling/gone
refused "read failed, dangling link" "dangling/gone: .*not found" dangling dang
# a link that loops ends
rm -rf dist; mkdir -p dist/pwa loop; ln -s . loop/self
refused "loop" "too many levels of symbolic links" loop looped
# a tree deeper than 64 levels is refused by the depth limit
rm -rf dist deep; mkdir -p dist/pwa; d=deep; i=0
while [ $i -lt 66 ]; do d=$d/d; i=$((i + 1)); done
mkdir -p "$d"
refused "deep" "more than 64 levels" deep deeper
# the file that cannot be read
if [ "$(id -u)" != 0 ]; then
  mkdir -p src2; printf x > src2/secret; chmod 000 src2/secret
  refused "read failed" "Permission denied" src2 unread
fi
echo "gen-pwa pages: ok"

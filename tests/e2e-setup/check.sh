#!/bin/bash
# The e2e-setup action's scripts (.github/actions/e2e-setup), run by hand
# as its steps run them. Checked: npm ci retried when the connection drops
# (a fake npm; then the real npm against a registry that resets the first
# requests, once inside npm's own retries and once past them), not retried
# for a failure that is not the network's, a lock that does not match
# package.json or is missing fails, the Playwright minimum, the browsers'
# key changing with the Playwright version and not with the app, the
# browsers install retried, sdkmanager's cut repository index retried, and the stall
# tools' apt calls bounded (a
# stalled apt-get is stopped and the next attempt runs, pwa#163) and their packages kept
# between runs (a miss, a hit that asks the mirror for nothing, a cache of another libc6, a
# damaged package, the key, pwa#227). The action's YAML (setup-node, the cache) can
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

# --- retry.sh: sdkmanager's repository index cut short is a download failure (pwa#169)
cat > "$TMP/index-cut" <<'FAKE'
#!/bin/sh
n=$(cat "$FAKE_COUNT" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "$FAKE_COUNT"
if [ "$n" -le 1 ]; then
  echo "Warning: Errors during XML parse:" >&2
  echo "Warning: Additionally, the fallback loader failed to parse the XML." >&2
  echo "parsing problem. XML document structures must start and end within the same entity." >&2
  echo "Failed to find package 'system-images;android-34;default;x86_64'" >&2
  exit 1
fi
exit 0
FAKE
chmod +x "$TMP/index-cut"
rm -f "$TMP/count"
(E2E_ATTEMPTS=3 E2E_PAUSE_S=0 FAKE_COUNT="$TMP/count"; export E2E_ATTEMPTS E2E_PAUSE_S FAKE_COUNT
 . "$ACT/retry.sh"; retry "the SDK packages" "$TMP/index-cut") > "$TMP/out" 2>&1 \
  || fail "a repository index cut short was not retried" "$TMP/out"
[ "$(cat "$TMP/count")" = 2 ] || fail "the index case ran $(cat "$TMP/count") times, not 2"
grep -q 'the download failed (try 1 of 3)' "$TMP/out" \
  || fail "the index retry was not said" "$TMP/out"

# --- the stall tools: every apt call bounded, a stalled one stopped, the next attempt run;
# the packages kept between runs (pwa#227): a miss fetches and keeps them, a hit asks the mirror for nothing
mkdir -p "$TMP/f/bin"
cat > "$TMP/f/bin/sudo" <<'FAKE'
#!/bin/sh
exec "$@"
FAKE
cat > "$TMP/f/bin/dpkg-query" <<'FAKE'
#!/bin/sh
printf '%s' "${FAKE_LIBC:-2.39-0ubuntu8}"
FAKE
cat > "$TMP/f/bin/apt-get" <<'FAKE'
#!/bin/sh
# A fake apt-get over the archives directory E2E_APT_ARCHIVES.
# FAKE_STALL: the number of first calls (simulations apart) that never return (a mirror that stalls)
# -s install: the Inst lines of the packages; --download-only: a .deb the archives lack is
# taken from the "mirror" (listed in $FAKE_COUNT.fetched); a .deb whose bytes are not the
# mirror's is fetched again (apt checks an archive against the index's hashes); install: the
# .debs it used are listed in $FAKE_COUNT.installed, from the archives, else the mirror
ARGS="$*"
sim=no; dl=no; action=; pkgs=
while [ $# -gt 0 ]; do
  case $1 in
    -o) shift ;;
    -s) sim=yes ;;
    --download-only) dl=yes ;;
    -*) ;;
    update|install) action=$1 ;;
    *) pkgs="$pkgs $1" ;;
  esac
  shift
done
if [ "$sim" = no ]; then
  n=$(cat "$FAKE_COUNT" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "$FAKE_COUNT"
  echo "$ARGS" >> "$FAKE_COUNT.args"
  if [ "$n" -le "${FAKE_STALL:-0}" ]; then exec sleep 60; fi
fi
debs_of() { # <package> -> name version arch lines
  case $1 in
    gdb) echo "gdb 15.1-1 amd64"; echo "gdb-common 1:15.1-1 all" ;;
    elfutils) echo "elfutils 0.190-1 amd64" ;;
    libc6-dbg=*) echo "libc6-dbg ${1#libc6-dbg=} amd64" ;;
    rr) echo "rr 5.7.0-1 amd64" ;;
  esac
}
for pkg in $pkgs; do
  debs_of "$pkg" | while read -r name version arch; do
    case $version in *:*) fversion=${version%%:*}%3a${version#*:} ;; *) fversion=$version ;; esac
    file=${name}_${fversion}_${arch}.deb
    if [ "$sim" = yes ]; then
      echo "Inst $name (${version} Ubuntu:24.04/noble-updates [$arch])"
    elif [ "$action" = install ]; then
      if [ "$dl" = no ]; then
        if [ "$(cat "$E2E_APT_ARCHIVES/$file" 2>/dev/null)" != "mirror:$file" ]; then echo "$file" >> "$FAKE_COUNT.fetched"; fi
        echo "$file" >> "$FAKE_COUNT.installed"
      elif [ "$(cat "$E2E_APT_ARCHIVES/$file" 2>/dev/null)" != "mirror:$file" ]; then
        echo "$file" >> "$FAKE_COUNT.fetched"
        echo "mirror:$file" > "$E2E_APT_ARCHIVES/$file"
      fi
    fi
  done
done
exit 0
FAKE
chmod +x "$TMP/f/bin/sudo" "$TMP/f/bin/dpkg-query" "$TMP/f/bin/apt-get"
stall() { # <stalled calls> <debs dir> [libc6] -> stall-tools.sh install, an empty archives directory and state
  rm -rf "$TMP/count" "$TMP/count.args" "$TMP/count.fetched" "$TMP/count.installed" "$TMP/f/arch" "$TMP/f/state"
  mkdir -p "$TMP/f/arch"
  PATH="$TMP/f/bin:$PATH" FAKE_COUNT="$TMP/count" FAKE_STALL=$1 FAKE_LIBC=${3:-2.39-0ubuntu8} E2E_APT_HANG_S=1 E2E_PAUSE_S=0 \
    E2E_APT_ARCHIVES="$TMP/f/arch" E2E_STALL_STATE="$TMP/f/state" STALL_DEBS_DIR=$2 "$ACT/stall-tools.sh" install > "$TMP/out" 2>&1
}
stall_key() { # <libc6> -> the key of stall-tools.sh key, in $TMP/f/key
  rm -rf "$TMP/count" "$TMP/count.args" "$TMP/f/state"; : > "$TMP/f/key"
  PATH="$TMP/f/bin:$PATH" FAKE_COUNT="$TMP/count" FAKE_LIBC=$1 E2E_PAUSE_S=0 E2E_STALL_STATE="$TMP/f/state" \
    GITHUB_OUTPUT="$TMP/f/key" "$ACT/stall-tools.sh" key > "$TMP/out" 2>&1
}
stall 1 "$TMP/f/debs1" || fail "stall-tools.sh failed after a stalled update" "$TMP/out"
grep -q 'apt-get update: apt-get did not return in 1s and was stopped (try 1 of 3)' "$TMP/out" || fail "the stalled update was not stopped" "$TMP/out"
grep -q 'installed=yes' "$TMP/out" || fail "the next attempt did not install" "$TMP/out"
[ "$(grep -c '^-o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o Acquire::Retries=3 update -q$' "$TMP/count.args")" = 2 ] || fail "the update did not run twice, bounded" "$TMP/count.args"
# update twice, then a download and an install of each of the 3 groups
[ "$(wc -l < "$TMP/count.args")" = 8 ] || fail "apt-get ran $(wc -l < "$TMP/count.args") times, not 8" "$TMP/count.args"
[ "$(grep -c '^-o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o Acquire::Retries=3 ' "$TMP/count.args")" = 8 ] || fail "an apt call without apt's own bounds" "$TMP/count.args"
grep -q 'install -y -q --no-upgrade libc6-dbg=2.39-0ubuntu8$' "$TMP/count.args" || fail "libc6-dbg is not pinned to the installed libc6" "$TMP/count.args"
# every call stalls: three tries of the update, then the job goes on (exit 0) saying why
stall 1000 "$TMP/f/debs2" || fail "stall-tools.sh failed the job when every call stalled" "$TMP/out"
grep -q 'installed=no' "$TMP/out" || fail "installed=no not said" "$TMP/out"
grep -q 'gdb and elfutils are not installed' "$TMP/out" || fail "the missing tools not said" "$TMP/out"
[ "$(grep -c ' update -q$' "$TMP/count.args")" = 3 ] || fail "the update was not tried 3 times" "$TMP/count.args"

# a miss: the mirror is asked for each of the 5 packages once, and they are kept
stall 0 "$TMP/f/cache" || fail "a miss" "$TMP/out"
grep -q '^Stall tools: 0 of 5 packages restored from the cache$' "$TMP/out" || fail "a miss not said" "$TMP/out"
[ "$(sort "$TMP/count.fetched" | uniq | wc -l)" = 5 ] && [ "$(wc -l < "$TMP/count.fetched")" = 5 ] || fail "the mirror was not asked for each package once" "$TMP/count.fetched"
[ "$(ls "$TMP/f/cache" | wc -l)" = 5 ] || fail "a miss did not keep the 5 packages" "$TMP/out"
[ -f "$TMP/f/cache/gdb-common_1%3a15.1-1_all.deb" ] && [ -f "$TMP/f/cache/libc6-dbg_2.39-0ubuntu8_amd64.deb" ] || fail "the kept names (an epoch is %3a)" "$TMP/out"
grep -q 'installed=yes' "$TMP/out" || fail "a miss did not install" "$TMP/out"
# a hit: the mirror is asked for nothing, and the same 5 packages are installed
stall 0 "$TMP/f/cache" || fail "a hit" "$TMP/out"
grep -q '^Stall tools: 5 of 5 packages restored from the cache$' "$TMP/out" || fail "a hit not said" "$TMP/out"
[ ! -s "$TMP/count.fetched" ] || fail "a hit asked the mirror" "$TMP/count.fetched"
[ "$(sort -u "$TMP/count.installed" | wc -l)" = 5 ] || fail "a hit did not install the 5 packages" "$TMP/count.installed"
# a cache of another libc6 (the image moved): libc6-dbg of the installed one only, from the mirror;
# the old one is neither installed nor kept
stall 0 "$TMP/f/cache" 2.39-0ubuntu7 || fail "a cache of another libc6" "$TMP/out"
grep -q '^Stall tools: 4 of 5 packages restored from the cache$' "$TMP/out" || fail "the other libc6 was trusted" "$TMP/out"
[ "$(cat "$TMP/count.fetched")" = libc6-dbg_2.39-0ubuntu7_amd64.deb ] || fail "the mirror was asked for more or less than libc6-dbg of the installed libc6" "$TMP/count.fetched"
! grep -q 'ubuntu8' "$TMP/count.installed" || fail "libc6-dbg of the other libc6 was installed" "$TMP/count.installed"
[ -f "$TMP/f/cache/libc6-dbg_2.39-0ubuntu7_amd64.deb" ] && [ ! -e "$TMP/f/cache/libc6-dbg_2.39-0ubuntu8_amd64.deb" ] || fail "the cache was not rewritten for the installed libc6" "$TMP/out"
# a damaged cached package: apt's own check fetches it again
stall 0 "$TMP/f/cache" 2.39-0ubuntu7 || fail "a hit before the damage" "$TMP/out"
printf 'damaged' > "$TMP/f/cache/rr_5.7.0-1_amd64.deb"
stall 0 "$TMP/f/cache" 2.39-0ubuntu7 || fail "a damaged package" "$TMP/out"
[ "$(cat "$TMP/count.fetched")" = rr_5.7.0-1_amd64.deb ] || fail "a damaged package was trusted" "$TMP/count.fetched"
# the key names the packages' versions and the libc6: it moves with either
stall_key 2.39-0ubuntu8 || fail "the key" "$TMP/out"
KEY8=$(cat "$TMP/f/key")
echo "$KEY8" | grep -q '^key=stall-tools-linux-x64-libc6-2.39-0ubuntu8-5-[0-9a-f]\{16\}$' || fail "the key" "$TMP/f/key"
stall_key 2.39-0ubuntu7 || fail "the key of another libc6" "$TMP/out"
[ "$(cat "$TMP/f/key")" != "$KEY8" ] || fail "the key did not move with the libc6" "$TMP/f/key"
stall_key 2.39-0ubuntu8 || fail "the key again" "$TMP/out"
[ "$(cat "$TMP/f/key")" = "$KEY8" ] || fail "the key is not the same for the same packages" "$TMP/f/key"
rm -rf "$TMP/f/state"; : > "$TMP/f/key"
PATH="$TMP/f/bin:$PATH" FAKE_COUNT="$TMP/count" FAKE_STALL=1000 E2E_APT_HANG_S=1 E2E_PAUSE_S=0 E2E_STALL_STATE="$TMP/f/state" GITHUB_RUN_ID=7 \
  GITHUB_OUTPUT="$TMP/f/key" "$ACT/stall-tools.sh" key > "$TMP/out" 2>&1 || fail "a key with a mirror that stalls failed the job" "$TMP/out"
grep -q '^key=stall-tools-unresolved-7-' "$TMP/f/key" || fail "the key of an index that could not be updated" "$TMP/f/key"

# --- the Japanese font: a miss fetches the pinned deb, a hit fetches nothing (pwa#226)
mkdir -p "$TMP/j/root/usr/share/fonts/opentype/ipafont-gothic" "$TMP/j/root/DEBIAN"
printf 'font one' > "$TMP/j/root/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf"
printf 'font two' > "$TMP/j/root/usr/share/fonts/opentype/ipafont-gothic/ipagp.ttf"
printf 'Package: fonts-ipafont-gothic\nVersion: 00303-21ubuntu1\nArchitecture: all\nMaintainer: t <t@example.com>\nDescription: test\n' > "$TMP/j/root/DEBIAN/control"
dpkg-deb -b "$TMP/j/root" "$TMP/j/good.deb" > /dev/null
printf 'other' > "$TMP/j/root/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf"
dpkg-deb -b "$TMP/j/root" "$TMP/j/bad.deb" > /dev/null
GOOD_SHA=$(sha256sum "$TMP/j/good.deb" | cut -d' ' -f1)
FILES_SUMS="$(printf 'font one' | sha256sum | cut -d' ' -f1)  ipag.ttf
$(printf 'font two' | sha256sum | cut -d' ' -f1)  ipagp.ttf"
font() { # <urls> <fonts dir> -> japanese-font.sh install with the test's pins, HOME in $TMP/j/home
  E2E_FONT_URLS=$1 E2E_FONT_DEB_SHA256=$GOOD_SHA E2E_FONT_FILES_SHA256=$FILES_SUMS \
    HOME="$TMP/j/home" FONT_DIR=$2 "$ACT/japanese-font.sh" install > "$TMP/out" 2>&1
}
# fontconfig stand-ins: the test fonts are not fonts, so fc-list names the files of the
# user's fonts directory as a real fontconfig names a real font, and a machine that
# already has IPAGothic cannot make the check pass (CI failed on a runner without it)
mkdir -p "$TMP/j/bin"
printf '#!/bin/sh\nexit 0\n' > "$TMP/j/bin/fc-cache"
printf '#!/bin/sh\nls "$HOME"/.local/share/fonts/pwa-e2e-japanese/*.ttf 2>/dev/null\n' > "$TMP/j/bin/fc-list"
chmod +x "$TMP/j/bin/fc-cache" "$TMP/j/bin/fc-list"
rm -rf "$TMP/j/home"; mkdir -p "$TMP/j/home"
OLDPATH=$PATH; PATH="$TMP/j/bin:$PATH"
font "file://$TMP/j/good.deb" "$TMP/j/cache" || fail "a miss with a good deb" "$TMP/out"
grep -q '[0-9] downloaded$' "$TMP/out" || fail "a miss said it downloaded nothing" "$TMP/out"
[ -f "$TMP/j/cache/ipag.ttf" ] && [ -f "$TMP/j/home/.local/share/fonts/pwa-e2e-japanese/ipagp.ttf" ] || fail "the fonts are not in the cache directory and the user's fonts"
font "file://$TMP/j/missing.deb" "$TMP/j/cache" || fail "a hit asked for a download" "$TMP/out"
grep -q 'from the cache, nothing downloaded' "$TMP/out" || fail "a hit was not said" "$TMP/out"
printf 'damaged' > "$TMP/j/cache/ipag.ttf"
font "file://$TMP/j/good.deb" "$TMP/j/cache" || fail "a damaged cache was not fetched again" "$TMP/out"
grep -q '[0-9] downloaded$' "$TMP/out" || fail "a damaged cache was trusted" "$TMP/out"
font "file://$TMP/j/missing.deb file://$TMP/j/good.deb" "$TMP/j/cache2" || fail "the second URL was not tried" "$TMP/out"
grep -q 'missing.deb: not fetched' "$TMP/out" || fail "the first URL's failure was not said" "$TMP/out"
font "file://$TMP/j/bad.deb" "$TMP/j/cache3" && fail "a deb with another hash passed" "$TMP/out"
grep -q 'could not be fetched from any URL' "$TMP/out" || fail "the message of a wrong hash" "$TMP/out"
[ ! -e "$TMP/j/cache3" ] || fail "a wrong deb left a cache directory"
font "file://$TMP/j/missing.deb" "$TMP/j/cache4" && fail "no URL working passed" "$TMP/out"
GITHUB_OUTPUT="$TMP/j/key" "$ACT/japanese-font.sh" key
grep -q '^key=japanese-font-ipafont-gothic-00303-21ubuntu1-71e63f0f88cc$' "$TMP/j/key" || fail "the key" "$TMP/j/key"

# fontconfig listing none of our files fails the step, though another IPAGothic is installed
printf '#!/bin/sh\necho /usr/share/fonts/opentype/ipafont-gothic/ipag.ttf\n' > "$TMP/j/bin/fc-list"
font "file://$TMP/j/good.deb" "$TMP/j/cache5" && fail "a font fontconfig does not list from our directory passed" "$TMP/out"
grep -q 'fontconfig lists no Japanese font after the install' "$TMP/out" || fail "the message of an unlisted font" "$TMP/out"
PATH=$OLDPATH

echo "e2e-setup: all checks passed"

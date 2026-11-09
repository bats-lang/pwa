#!/bin/bash
# The minimum SDK level of the generated Android project (bats-lang/pwa#308):
# build-android.sh, written by create_android_locked_min_sdk with level 29,
# leaves android/variables.gradle with minSdkVersion = 29 after `cap add
# android` and before anything else of the build; the one written by
# create_android_locked (no level) leaves the file as Capacitor wrote it.
# Checked with a stand-in corepack that records its arguments, makes the
# android/ project `cap add android` makes (variables.gradle as Capacitor
# 8.5.3's template writes it, minSdkVersion = 24) and ends the script
# (status 42) at the step after, `cap sync android`, so reaching 42 means
# everything before it passed:
#   1. android-min-sdk-29-sets-variables-gradle: level 29 -> the line is
#      minSdkVersion = 29 and no other line of the file changed;
#   2. android-min-sdk-none-keeps-capacitors-line: no level -> the file is
#      byte for byte what Capacitor wrote;
#   3. android-min-sdk-missing-line-stops-the-build: level 29 and a
#      variables.gradle with no minSdkVersion line -> the script fails with
#      a message and does not reach cap sync (a setting is never ignored).
# usage: tests/android-min-sdk/check.sh <project with level 29> <project with no level>
set -eu
HANG_GUARD_S=300
[ $# = 2 ] || { echo "usage: $0 <project with level 29> <project with no level>" >&2; exit 2; }
WITH=$(cd "$1" && pwd)
WITHOUT=$(cd "$2" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; shift; for f in "$@"; do echo "--- $f"; cat "$f"; done; exit 1; }

# variables.gradle of @capacitor/android 8.5.3's template, the one `cap add android` copies
cat > "$TMP/capacitor.gradle" <<'GRADLE'
ext {
    minSdkVersion = 24
    compileSdkVersion = 36
    targetSdkVersion = 36
    androidxActivityVersion = '1.11.0'
    androidxAppCompatVersion = '1.7.1'
    androidxCoordinatorLayoutVersion = '1.3.0'
    androidxCoreVersion = '1.17.0'
    androidxFragmentVersion = '1.8.9'
    coreSplashScreenVersion = '1.2.0'
    androidxWebkitVersion = '1.14.0'
    junitVersion = '4.13.2'
    androidxJunitVersion = '1.3.0'
    androidxEspressoCoreVersion = '3.7.0'
    cordovaAndroidVersion = '14.0.1'
}
GRADLE
# the same with level 29
{ echo 'ext {'; echo '    minSdkVersion = 29'; sed '1,2d' "$TMP/capacitor.gradle"; } > "$TMP/expected-29.gradle"
# a file with no minSdkVersion line
sed '2d' "$TMP/capacitor.gradle" > "$TMP/no-line.gradle"
grep -q minSdkVersion "$TMP/no-line.gradle" && fail "the fixture without the line has it"

# corepack pnpm@version <args>: recorded; `exec cap add android` makes the
# project Capacitor makes, with the variables.gradle named by $STUB_VARIABLES;
# `exec cap sync android` ends the script with 42
mkdir -p "$TMP/bin"
cat > "$TMP/bin/corepack" <<'STUB'
#!/bin/sh
shift # pnpm@version
echo "pnpm $*" >> "$STUB_LOG"
case "$*" in
  "exec cap add android")
    mkdir -p android/app/src/main/java/dev/bats/example
    : > android/app/src/main/java/dev/bats/example/MainActivity.java
    printf '<manifest><application><activity></activity></application></manifest>\n' > android/app/src/main/AndroidManifest.xml
    : > android/app/build.gradle
    cp "$STUB_VARIABLES" android/variables.gradle ;;
  "exec cap sync android") exit 42 ;;
esac
STUB
chmod +x "$TMP/bin/corepack"

# project <source> <dir>: a copy of the generated project with the lock it needs
# and a fetch-pnpm.sh that only names the pnpm (its download is tested by tests/android/pnpm.sh)
project() {
  mkdir -p "$2"; cp -R "$1/." "$2"
  echo "lockfileVersion: '9.0'" > "$2/pnpm-lock.yaml"
  printf '%s\n' 'pnpm="corepack pnpm@12.9.1"' > "$2/fetch-pnpm.sh"
}
run() { # <dir> <variables.gradle> -> status in $TMP/status, output in $TMP/out
  : > "$STUB_LOG"
  set +e
  (cd "$1" && STUB_VARIABLES="$2" PATH="$TMP/bin:$PATH" timeout "$HANG_GUARD_S" sh ./build-android.sh <&-) > "$TMP/out" 2>&1
  echo $? > "$TMP/status"
  set -e
}
export STUB_LOG="$TMP/log"

# 1. level 29
project "$WITH" "$TMP/p1"
run "$TMP/p1" "$TMP/capacitor.gradle"
[ "$(cat "$TMP/status")" = 42 ] || fail "android-min-sdk-29-sets-variables-gradle: status $(cat "$TMP/status"), not 42" "$TMP/out"
grep -qx '    minSdkVersion = 29' "$TMP/p1/android/variables.gradle" || fail "android-min-sdk-29-sets-variables-gradle: no minSdkVersion = 29" "$TMP/p1/android/variables.gradle"
cmp -s "$TMP/p1/android/variables.gradle" "$TMP/expected-29.gradle" || fail "android-min-sdk-29-sets-variables-gradle: another line changed" "$TMP/p1/android/variables.gradle"
echo "PASS android-min-sdk-29-sets-variables-gradle"

# 2. no level
project "$WITHOUT" "$TMP/p2"
run "$TMP/p2" "$TMP/capacitor.gradle"
[ "$(cat "$TMP/status")" = 42 ] || fail "android-min-sdk-none-keeps-capacitors-line: status $(cat "$TMP/status"), not 42" "$TMP/out"
cmp -s "$TMP/p2/android/variables.gradle" "$TMP/capacitor.gradle" || fail "android-min-sdk-none-keeps-capacitors-line: the file is not Capacitor's" "$TMP/p2/android/variables.gradle"
grep -qx '    minSdkVersion = 24' "$TMP/p2/android/variables.gradle" || fail "android-min-sdk-none-keeps-capacitors-line: not Capacitor's 24" "$TMP/p2/android/variables.gradle"
echo "PASS android-min-sdk-none-keeps-capacitors-line"

# 3. level 29 and no line to set
project "$WITH" "$TMP/p3"
run "$TMP/p3" "$TMP/no-line.gradle"
[ "$(cat "$TMP/status")" = 1 ] || fail "android-min-sdk-missing-line-stops-the-build: status $(cat "$TMP/status"), not 1" "$TMP/out"
grep -q "no minSdkVersion line" "$TMP/out" || fail "android-min-sdk-missing-line-stops-the-build: not said" "$TMP/out"
! grep -q "cap sync" "$STUB_LOG" || fail "android-min-sdk-missing-line-stops-the-build: the build went on" "$STUB_LOG"
echo "PASS android-min-sdk-missing-line-stops-the-build"

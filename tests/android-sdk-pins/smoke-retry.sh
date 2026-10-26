#!/bin/bash
# The smoke test's emulator step run again when the action's install fails
# before an emulator started (bats-lang/pwa#214; area keyword android-smoke).
# A stand-in sdkmanager serves a cut-short manifest on its first call and the
# whole one after; a stand-in for the action installs with it (as the action
# does: `sh -c "sdkmanager --install ... > /dev/null"`), makes the marker by the
# very line of android.yml's pre-emulator-launch-script, and runs a test. The
# steps' order is android.yml's (attempt 1 with continue-on-error, "Whether the
# emulator step runs again" with the very command of that step, attempt 2 only
# when it passed); the decision is the bats tool's `again`. Shell, since it drives
# a built binary against files (check.sh is the precedent); the tool is bats.
#
# usage: tests/android-sdk-pins/smoke-retry.sh <android-sdk-pins binary>
set -eu
BIN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
HERE=$(cd "$(dirname "$0")" && pwd)
YML="$HERE/../../.github/workflows/android.yml"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# android.yml has the two attempts and the decision between them
[ "$(grep -c 'name: Run the app on an emulator (attempt [12] of 2)' "$YML")" = 2 ] || fail "android.yml: not two attempts"
grep -q 'ANDROID_SMOKE_ATTEMPTS: .2.' "$YML" || fail "android.yml: the attempts are not 2"
DECIDE=$(grep 'sdk-pins-bin/android-sdk-pins" again ' "$YML" | head -1 | cut -c 11-)
MARKER=$(grep 'touch "\$RUNNER_TEMP/emulator-installed"' "$YML" | head -1 | cut -c 13-)
[ -n "$DECIDE" ] && [ -n "$MARKER" ] || fail "android.yml: no decision or no marker"

export GITHUB_WORKSPACE="$TMP/workspace" RUNNER_TEMP="$TMP/runner"
mkdir -p "$GITHUB_WORKSPACE/sdk-pins-bin" "$RUNNER_TEMP" "$TMP/bin"
cp "$BIN" "$GITHUB_WORKSPACE/sdk-pins-bin/android-sdk-pins"

# Google's manifest, whole and cut short (the real failure: sys-img2-3.xml)
printf '<?xml version="1.0"?>\n<sdk:sdk-repository>\n<remotePackage path="system-images;android-34;default;x86_64"/>\n</sdk:sdk-repository>\n' > "$TMP/whole.xml"
printf '<?xml version="1.0"?>\n<sdk:sdk-repository>\n<remotePackage path="system-im' > "$TMP/cut.xml"

# sdkmanager: the manifest of the Nth call is cut.xml for the first CUT_CALLS calls
cat > "$TMP/bin/sdkmanager" <<'SDK'
#!/bin/sh
n=$(( $(cat "$STATE/calls" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$STATE/calls"
if [ "$n" -le "$CUT_CALLS" ]; then manifest="$FIXTURES/cut.xml"; else manifest="$FIXTURES/whole.xml"; fi
if ! grep -q '</sdk:sdk-repository>' "$manifest"; then
  echo "Warning: https://dl.google.com/android/repository/sys-img/google-tv/sys-img2-3.xml parsing problem. XML document structures must start and end within the same entity." >&2
  echo "Warning: Failed to find package '$2'" >&2
  exit 1
fi
echo "Installing $2 (stdout, which the action sends to /dev/null)"
SDK
chmod +x "$TMP/bin/sdkmanager"

# the action: the install group, then the pre-emulator-launch-script's marker,
# then the test (TEST_RESULT)
cat > "$TMP/bin/action" <<'ACTION'
#!/bin/sh
echo "##[group]Install Android SDK"
if ! sh -c "sdkmanager --install 'system-images;android-34;default;x86_64' --channel=0 > /dev/null"; then
  echo "##[error]The process '/usr/bin/sh' failed with exit code 1"
  echo "##[endgroup]"
  exit 1
fi
echo "##[endgroup]"
eval "$MARKER_LINE"
echo "emulator started; the test runs"
[ "$TEST_RESULT" = pass ] || { echo "the test failed"; exit 1; }
ACTION
chmod +x "$TMP/bin/action"

# workflow <android.yml>: its steps in order; the second attempt and the
# decision exist only when the file has the step "attempt 2 of 2"
workflow() {
  echo "== attempt 1 of 2"
  set +e; action; first=$?; set -e
  [ "$first" != 0 ] || return 0
  grep -q 'name: Run the app on an emulator (attempt 2 of 2)' "$1" || return "$first"
  echo "== Whether the emulator step runs again"
  set +e; ANDROID_SMOKE_ATTEMPT=1 ANDROID_SMOKE_ATTEMPTS=2 sh -c "$DECIDE"; decided=$?; set -e
  [ "$decided" = 0 ] || return "$decided"
  echo "== attempt 2 of 2"
  action
}
action() { PATH="$TMP/bin:$PATH" MARKER_LINE="$MARKER" sh "$TMP/bin/action"; }

# run <name> <cut calls> <test result> <android.yml>
run() {
  name=$1
  export STATE="$TMP/$name" FIXTURES="$TMP" CUT_CALLS=$2 TEST_RESULT=$3
  mkdir -p "$STATE"; rm -f "$RUNNER_TEMP/emulator-installed"
  set +e; (workflow "$4") > "$TMP/$name.out" 2>&1; RC=$?; set -e
  echo "######## $name: $2 cut-short manifest(s), test $3, $(basename "$4") (exit $RC, sdkmanager called $(cat "$STATE/calls") times)"
  cat "$TMP/$name.out"
}

# 1. a cut-short manifest on the first call: two attempts, a pass
run cut-then-whole 1 pass "$YML"
[ "$RC" = 0 ] || fail "cut-then-whole: exit $RC"
[ "$(cat "$TMP/cut-then-whole/calls")" = 2 ] || fail "cut-then-whole: not two attempts"
grep -q 'attempt 1 of 2 failed before an emulator started: running attempt 2 of 2' "$TMP/cut-then-whole.out" || fail "cut-then-whole: attempt 2 of 2 not said"
grep -q 'parsing problem' "$TMP/cut-then-whole.out" || fail "cut-then-whole: the first attempt's sdkmanager output is not kept"

# 2. the injection: android.yml without the second attempt, the same fixture fails
grep -v 'attempt 2 of 2)' "$YML" > "$TMP/android-no-retry.yml"
run cut-no-retry 1 pass "$TMP/android-no-retry.yml"
[ "$RC" != 0 ] || fail "cut-no-retry: passed with no retry"
[ "$(cat "$TMP/cut-no-retry/calls")" = 1 ] || fail "cut-no-retry: not one attempt"

# 3. a failure of the test after the emulator started is not run again
run test-fails 0 fail "$YML"
[ "$RC" = 1 ] || fail "test-fails: exit $RC"
[ "$(cat "$TMP/test-fails/calls")" = 1 ] || fail "test-fails: run again"
grep -q "the test's verdict, not run again" "$TMP/test-fails.out" || fail "test-fails: not said"

# 4. the install fails on both attempts: two attempts, a failure
run always-cut 2 pass "$YML"
[ "$RC" != 0 ] || fail "always-cut: passed"
[ "$(cat "$TMP/always-cut/calls")" = 2 ] || fail "always-cut: not two attempts"

# 5. the decision when no attempt is left, and the usage
set +e
ANDROID_SMOKE_ATTEMPT=2 ANDROID_SMOKE_ATTEMPTS=2 "$BIN" again "$TMP/none" > "$TMP/last.out" 2>&1; LAST=$?
"$BIN" again > "$TMP/usage.out" 2>&1; USAGE=$?
set -e
echo "== no attempt left (exit $LAST)"; cat "$TMP/last.out"
[ "$LAST" = 1 ] || fail "no attempt left: exit $LAST"
grep -q 'attempt 2 of 2 failed before an emulator started, and no attempt is left' "$TMP/last.out" || fail "no attempt left: not said"
[ "$USAGE" = 2 ] || fail "again without a marker: exit $USAGE"
echo "OK: the emulator step runs again after an install that failed before an emulator started, and not after a test that failed"

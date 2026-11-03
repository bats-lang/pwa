#!/bin/sh
# android.yml's build step runs the build again when it failed resolving a
# Gradle dependency (bats-lang/pwa#276; area keyword android-gradle-retry).
# The lines between its `# retry-begin` and `# retry-end` markers are taken
# from the real workflow and run with bash (as the runner's `shell: bash`
# does) against a stand-in build-android.sh and a stand-in gradlew:
#   - a first attempt that fails with Gradle's "Could not find" and a second
#     that passes: the step passes, one warning names attempt 1, the daemon
#     was stopped and the metadata cache removed (the downloaded files stay),
#     and the log holds both attempts;
#   - a failure that is no resolution failure: one attempt, the step fails;
#   - a resolution failure every time: three attempts, then the step fails.
# Run from anywhere.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
workflow=$here/../../.github/workflows/android.yml
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# the step's lines, without their indentation
sed -n '/^ *# retry-begin$/,/^ *# retry-end$/p' "$workflow" | sed 's/^          //' > "$tmp/step.sh"
[ "$(grep -c '^# retry-begin$' "$tmp/step.sh")" = 1 ] || fail "the workflow has not exactly one retry-begin marker"
[ "$(grep -c '^# retry-end$' "$tmp/step.sh")" = 1 ] || fail "the workflow has not exactly one retry-end marker"

# play <name> <first attempts' output...>: a fresh home and project whose
# build prints the given outputs in turn (the last one for every attempt after
# them) and passes only when the output is the word "ok"
play() {
  name=$1; shift
  d=$tmp/$name
  mkdir -p "$d/home/.gradle/caches/modules-2/metadata-2.107" "$d/home/.gradle/caches/modules-2/files-2.1" "$d/project/android" "$d/temp"
  echo missing > "$d/home/.gradle/caches/modules-2/metadata-2.107/module-metadata.bin"
  echo jar > "$d/home/.gradle/caches/modules-2/files-2.1/kept.jar"
  n=0
  for out in "$@"; do
    n=$((n + 1))
    printf '%s\n' "$out" > "$d/project/answer$n"
  done
  cat > "$d/project/build-android.sh" <<'BUILD'
#!/bin/sh
# the stand-in build: answer N is the Nth call's output
dir=$(dirname "$0")
echo x >> "$dir/calls"
n=$(wc -l < "$dir/calls" | tr -d ' ')
[ -f "$dir/answer$n" ] || n=$(ls "$dir" | grep -c '^answer')
cat "$dir/answer$n"
[ "$(cat "$dir/answer$n")" = ok ]
BUILD
  cat > "$d/project/android/gradlew" <<'GRADLEW'
#!/bin/sh
echo "$@" >> "$(dirname "$0")/../gradlew-calls"
GRADLEW
  chmod +x "$d/project/android/gradlew"
  status=0
  HOME=$d/home RUNNER_TEMP=$d/temp RETRY_DELAY=0 BUILD_SCRIPT=$d/project/build-android.sh GRADLE_PROJECT=$d/project/android \
    bash -e -o pipefail "$tmp/step.sh" > "$d/out" 2>&1 || status=$?
  calls=$(wc -l < "$d/project/calls" | tr -d ' ')
}

missing='> Could not find org.jetbrains.kotlin:kotlin-stdlib:2.2.0.'

# a first fetch that failed, then a pass
play flaky "$missing" ok
[ $status -eq 0 ] || fail "flaky: exit $status: $(cat "$d/out")"
[ "$calls" = 2 ] || fail "flaky: $calls attempts, not 2"
[ "$(grep -c '^::warning::Attempt 1 of 3 failed resolving a dependency' "$d/out")" = 1 ] || fail "flaky: no warning naming attempt 1: $(cat "$d/out")"
grep -q 'kotlin-stdlib' "$d/temp/build-android.log" || fail "flaky: the first attempt is not in the log"
[ "$(grep -c '^ok$' "$d/temp/build-android.log")" = 1 ] || fail "flaky: the second attempt is not in the log"
grep -qx -- '--stop' "$d/project/gradlew-calls" || fail "flaky: the Gradle daemon was not stopped"
[ ! -e "$d/home/.gradle/caches/modules-2/metadata-2.107" ] || fail "flaky: the metadata cache is still there"
[ -f "$d/home/.gradle/caches/modules-2/files-2.1/kept.jar" ] || fail "flaky: the downloaded files were removed"

# a failure that is not a resolution failure: not run again
play broken 'error: unresolved symbol in MainActivity.java'
[ $status -eq 1 ] || fail "broken: exit $status, not 1"
[ "$calls" = 1 ] || fail "broken: $calls attempts, not 1"
grep -q '^::error::The build failed on attempt 1 of 3, and not again' "$d/out" || fail "broken: no error naming attempt 1"
[ -f "$d/home/.gradle/caches/modules-2/metadata-2.107/module-metadata.bin" ] || fail "broken: the caches were touched"

# a resolution failure every time: bounded
play always "$missing"
[ $status -eq 1 ] || fail "always: exit $status, not 1"
[ "$calls" = 3 ] || fail "always: $calls attempts, not 3"
[ "$(grep -c '^::warning::Attempt' "$d/out")" = 2 ] || fail "always: not two warnings"
grep -q '^::error::The build failed on attempt 3 of 3, and not again' "$d/out" || fail "always: no error naming attempt 3"

# a pass at once: one attempt, no warning
play clean ok
[ $status -eq 0 ] && [ "$calls" = 1 ] || fail "clean: exit $status after $calls attempts"
grep -q '::warning::' "$d/out" && fail "clean: a warning"

echo "android-gradle-retry: ok"

#!/bin/bash
# queue-passed (bats-lang/pwa#215) against GitHub's own answers of the runs API
# (tests/queue-passed/answers, how they were fetched: answers/README): a passed
# queue run on the pushed sha is a skip with the run's url, and each of these
# runs everything: no merge_group run on the sha, one on another sha, one whose
# conclusion is failure, cancelled or skipped (what the queue's destroyed event
# ends with, quire#879), one still running, one of another workflow file, one
# of another event, an event other than push, a sha that is not a commit, a
# workflow ref that names no file, and an answer that is missing, empty, too
# big, not JSON or not an object. Each case names the reason it must give, so a
# case cannot pass by running everything for another cause.
# Shell, since it drives a built binary against files (tests/android-sdk-pins/check.sh
# is the precedent); the tool it tests is bats.
#
# usage: tests/queue-passed/check.sh <queue-passed binary>
set -eu
BIN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
HERE=$(cd "$(dirname "$0")" && pwd)
A=$HERE/answers
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAILED=0

REF=bats-lang/quire/.github/workflows/check.yml@refs/heads/main
PASSED=7fb2de0db6a22d79b672b2c75eb246400e5630d4
PASSED_URL=https://github.com/bats-lang/quire/actions/runs/40229598535

NO_PASS="no successful merge_group run of this workflow on this sha in the answer"
SKIP_REASON="the merge queue passed this commit in the run named in run-url"

# check <name> <skip|run> <reason> <url> <args of decide...>
check() {
  name=$1; want=$2; reason=$3; url=$4; shift 4
  set +e
  "$BIN" decide "$@" > "$TMP/out" 2> "$TMP/err"
  rc=$?
  set -e
  echo "== $name (exit $rc)"
  cat "$TMP/out"; cat "$TMP/err"
  if [ "$want" = skip ]; then
    printf 'skip=true\nrun-url=%s\nreason=%s\n' "$url" "$reason" > "$TMP/want"
  else
    printf 'skip=false\nrun-url=\nreason=%s\n' "$reason" > "$TMP/want"
  fi
  if [ "$rc" != 0 ] || ! cmp -s "$TMP/out" "$TMP/want"; then
    echo "FAIL $name: wanted exit 0 and"; cat "$TMP/want"
    FAILED=$((FAILED + 1))
  fi
}

# the pass, and the run it names
check passed skip "$SKIP_REASON" "$PASSED_URL" push "$PASSED" "$REF" "$A/passed.json"

# no merge_group run on the sha (the answer holds none, or a pull request's run
# of the same workflow and sha, which is no queue run)
check no-run run "$NO_PASS" - push ef2543d1d71064fe2264a6770ec9c9f13e8cd6f7 "$REF" "$A/none.json"
check other-event run "$NO_PASS" - push ef2543d1d71064fe2264a6770ec9c9f13e8cd6f7 "$REF" "$A/pull-request-run.json"
# runs of other shas that passed (the newest 30 of the queue's runs, three groups
# among them passed): no pass for this sha
check other-sha run "$NO_PASS" - push ef2543d1d71064fe2264a6770ec9c9f13e8cd6f7 "$REF" "$A/other-sha.json"
# the answer of one sha asked about its neighbour: the last digit changed
check other-sha-one-digit run "$NO_PASS" - push 7fb2de0db6a22d79b672b2c75eb246400e5630d5 "$REF" "$A/passed.json"
# conclusions that are no pass
check failure run "$NO_PASS" - push 11a267677e46569ee96d598444828d7c9d1b9034 "$REF" "$A/failure.json"
check cancelled run "$NO_PASS" - push 5d7d990a57c0ea7c70e8f55c6bf52cbf7bbdae69 "$REF" "$A/cancelled.json"
# the destroyed event's run is skipped (quire#879 run 40243573211), beside a cancelled one
# and a passed supersede.yml run of the same sha and event
check skipped run "$NO_PASS" - push 814f201fa3e60b7d7cdb14061d4d6d0638c10bca "$REF" "$A/destroyed.json"
check running run "$NO_PASS" - push e7e7a4bcb7c5339ffc2a5bcad48d39ed5c634275 "$REF" "$A/running.json"
# the pass is another workflow file's
check other-workflow run "$NO_PASS" - push "$PASSED" bats-lang/quire/.github/workflows/deploy.yml@refs/heads/main "$A/passed.json"
check other-workflow-prefix run "$NO_PASS" - push "$PASSED" bats-lang/quire/.github/workflows/chec@refs/heads/main "$A/passed.json"
# an event other than push never skips (the nightly run, a dispatch, a pull request, the queue's own)
for event in schedule workflow_dispatch pull_request merge_group pull_request_target Push push2 ""; do
  check "event-${event:-empty}" run "the event is not push: everything runs" - "$event" "$PASSED" "$REF" "$A/passed.json"
done
# a sha that is not 40 lower case hex digits
check sha-short run "the commit is not 40 lower case hex digits: everything runs" - push 7fb2de0 "$REF" "$A/passed.json"
check sha-upper run "the commit is not 40 lower case hex digits: everything runs" - push 7FB2DE0DB6A22D79B672B2C75EB246400E5630D4 "$REF" "$A/passed.json"
check sha-long run "the commit is not 40 lower case hex digits: everything runs" - push "${PASSED}0" "$REF" "$A/passed.json"
check sha-empty run "the commit is not 40 lower case hex digits: everything runs" - push "" "$REF" "$A/passed.json"
# a workflow ref that names no file
for ref in "" check.yml@main bats-lang/quire bats-lang/quire/.github/workflows/check.yml bats-lang/quire/@refs/heads/main; do
  case $ref in bats-lang/quire/.github/workflows/check.yml) want=skip ;; *) want=run ;; esac
  if [ "$want" = skip ]; then
    check "ref-${ref:-empty}" skip "$SKIP_REASON" "$PASSED_URL" push "$PASSED" "$ref" "$A/passed.json"
  else
    check "ref-${ref:-empty}" run "the workflow ref is not owner/repo/path@ref: everything runs" - push "$PASSED" "$ref" "$A/passed.json"
  fi
done

# an answer that cannot be used
printf 'not json at all\n' > "$TMP/not-json"
printf '{"total_count": 1, "workflow_runs": [' > "$TMP/cut"
printf '[]\n' > "$TMP/array"
printf '{"total_count": 0}\n' > "$TMP/no-runs-member"
printf '{"workflow_runs": 5}\n' > "$TMP/runs-not-array"
printf '{"workflow_runs": [1, "a", null, [], {"event": 5, "head_sha": 5, "path": 5, "conclusion": 5}]}\n' > "$TMP/odd-members"
: > "$TMP/empty"
check missing run "the runs answer cannot be opened" - push "$PASSED" "$REF" "$TMP/does-not-exist"
check empty run "the runs answer is empty or its size cannot be read" - push "$PASSED" "$REF" "$TMP/empty"
check not-json run "the runs answer is not JSON" - push "$PASSED" "$REF" "$TMP/not-json"
check cut-off run "the runs answer is not JSON" - push "$PASSED" "$REF" "$TMP/cut"
check array run "the runs answer is not a JSON object" - push "$PASSED" "$REF" "$TMP/array"
check no-runs-member run "$NO_PASS" - push "$PASSED" "$REF" "$TMP/no-runs-member"
check runs-not-array run "$NO_PASS" - push "$PASSED" "$REF" "$TMP/runs-not-array"
check odd-members run "$NO_PASS" - push "$PASSED" "$REF" "$TMP/odd-members"
check directory run "the runs answer cannot be read whole" - push "$PASSED" "$REF" "$TMP"

# the size bound: 1048576 bytes are read (the pass, padded with blanks), one more is not
python3 -I - "$A/passed.json" "$TMP/exact" "$TMP/over" <<'PY'
import sys
data = open(sys.argv[1], "rb").read().rstrip(b"\n")
open(sys.argv[2], "wb").write(data + b" " * (1048576 - len(data)))
open(sys.argv[3], "wb").write(data + b" " * (1048577 - len(data)))
PY
check exact-bound skip "$SKIP_REASON" "$PASSED_URL" push "$PASSED" "$REF" "$TMP/exact"
check over-bound run "the runs answer is over 1048576 bytes" - push "$PASSED" "$REF" "$TMP/over"

# arguments it does not take
for arguments in "" "decide" "decide push $PASSED $REF" "frobnicate push $PASSED $REF $A/passed.json" "decide push $PASSED $REF $A/passed.json extra"; do
  set +e
  # shellcheck disable=SC2086
  "$BIN" $arguments > "$TMP/out" 2> "$TMP/err"
  rc=$?
  set -e
  echo "== usage: ${arguments:-no arguments} (exit $rc)"; cat "$TMP/out"; cat "$TMP/err"
  if [ "$rc" != 2 ] || [ -s "$TMP/out" ]; then
    echo "FAIL usage: wanted exit 2 and nothing on stdout"
    FAILED=$((FAILED + 1))
  fi
done

if [ "$FAILED" != 0 ]; then
  echo "queue-passed: $FAILED case(s) FAILED"
  exit 1
fi
echo "queue-passed: all cases passed"

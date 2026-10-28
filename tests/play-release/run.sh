#!/bin/sh
# scripts/play-release.sh (bats-lang/pwa#90) against a stub of Play's edits API (stub.py):
# a release makes an edit, uploads the AAB's bytes, sets the internal
# track to a completed release of the uploaded version code with the
# notes, and commits without cancelling a review; a dry run validates and
# deletes the edit; a new version code that is not above every code on the
# track and in the bundles list (read from the API in the same edit) is
# refused with both numbers; a refused step deletes the edit and commits nothing;
# notes that are empty or over Play's 500 characters fail before Play is
# asked anything; another track is released to by its name, and production
# or a name that is no track's is refused before Play is asked; the notes
# the workflow gives (NOTES, else the first line of COMMIT_MESSAGE, cut to
# 500 characters) are made by the script and tested here; the workflow that
# calls the script pins every action by commit and holds the permissions
# contents: read and id-token: write and no other. Run from
# anywhere.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
release=$here/../../scripts/play-release.sh
tmp=$(mktemp -d)
pid=
trap '[ -z "$pid" ] || kill "$pid" 2>/dev/null; rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

head -c 3000 /dev/urandom > "$tmp/app.aab"
printf '\n  • One\n• Two “quoted”\n\n' > "$tmp/notes"
export PLAY_ACCESS_TOKEN=token-1 PLAY_PACKAGE=dev.bats.example
unset PLAY_TRACK

# stub <failing path suffix>...: a fresh stub and log; PLAY_API its address
stub() {
  if [ -n "$pid" ]; then kill "$pid"; wait "$pid" 2>/dev/null || true; fi
  rm -f "$tmp/port"
  : > "$tmp/log"
  python3 "$here/stub.py" "$tmp/port" "$tmp/log" "$@" &
  pid=$!
  i=0
  until [ -s "$tmp/port" ]; do
    i=$((i + 1))
    [ $i -lt 100 ] || fail "the stub did not start"
    sleep 0.1
  done
  PLAY_API=http://127.0.0.1:$(cat "$tmp/port")
  export PLAY_API
}
# requests: each request's method and path, one a line
requests() { jq -r '.method + " " + .path' "$tmp/log"; }
expect_requests() {
  printf '%s\n' "$@" > "$tmp/want"
  requests > "$tmp/got"
  diff "$tmp/want" "$tmp/got" || fail "$case: not the requests expected"
}
app=/androidpublisher/v3/applications/dev.bats.example

case="a release"
stub
"$release" "$tmp/app.aab" "$tmp/notes" > "$tmp/out" || fail "$case: failed"
expect_requests \
  "POST $app/edits" \
  "GET $app/edits/edit-1/tracks/internal" \
  "GET $app/edits/edit-1/bundles" \
  "POST /upload$app/edits/edit-1/bundles?uploadType=media" \
  "PUT $app/edits/edit-1/tracks/internal" \
  "POST $app/edits/edit-1:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW"
[ -z "$(jq -r 'select(.authorization != "Bearer token-1") | .path' "$tmp/log")" ] || fail "$case: a request without the token"
jq -r 'select(.method == "POST" and (.path | contains("/bundles"))) | .body' "$tmp/log" | base64 -d > "$tmp/sent.aab"
cmp "$tmp/app.aab" "$tmp/sent.aab" || fail "$case: the bundle sent is not the AAB"
[ "$(jq -r 'select(.method == "POST" and (.path | contains("/bundles"))) | .type' "$tmp/log")" = application/octet-stream ] || fail "$case: the bundle's type"
jq -r 'select(.method == "PUT") | .body' "$tmp/log" | base64 -d | jq -c . > "$tmp/track"
want='{"track":"internal","releases":[{"versionCodes":["4242"],"status":"completed","releaseNotes":[{"language":"en-US","text":"• One\n• Two “quoted”"}]}]}'
[ "$(cat "$tmp/track")" = "$want" ] || fail "$case: the track was $(cat "$tmp/track")"
grep -q "version code 4242" "$tmp/out" || fail "$case: did not say the version code"
echo "ok: $case"

case="a dry run"
stub
"$release" "$tmp/app.aab" "$tmp/notes" --dry-run > /dev/null || fail "$case: failed"
expect_requests \
  "POST $app/edits" \
  "GET $app/edits/edit-1/tracks/internal" \
  "GET $app/edits/edit-1/bundles" \
  "POST /upload$app/edits/edit-1/bundles?uploadType=media" \
  "PUT $app/edits/edit-1/tracks/internal" \
  "POST $app/edits/edit-1:validate" \
  "DELETE $app/edits/edit-1"
echo "ok: $case"

for step in GET:/tracks/internal GET:/bundles POST:/bundles PUT:/tracks/internal POST::validate; do
  case="a refused $step"
  stub "$step"
  if "$release" "$tmp/app.aab" "$tmp/notes" --dry-run > /dev/null 2> "$tmp/err"; then
    fail "$case: succeeded"
  fi
  grep -q "HTTP 400" "$tmp/err" || fail "$case: did not say the answer"
  grep -q "refused by the stub" "$tmp/err" || fail "$case: did not say Play's message"
  [ "$(requests | tail -1)" = "DELETE $app/edits/edit-1" ] || fail "$case: the edit was not deleted"
  if requests | grep -q ':commit'; then fail "$case: committed"; fi
  echo "ok: $case"
done

# codes_stub <track codes> <bundle codes> <uploaded code>: a stub whose Play
# already holds these codes and answers the upload with the last
codes_stub() {
  STUB_TRACK_CODES=$1 STUB_BUNDLE_CODES=$2 STUB_UPLOAD_CODE=$3
  export STUB_TRACK_CODES STUB_BUNDLE_CODES STUB_UPLOAD_CODE
  stub
  unset STUB_TRACK_CODES STUB_BUNDLE_CODES STUB_UPLOAD_CODE
}
# refused_code <what>: the release failed naming both numbers, did not set the
# track or commit, and deleted the edit
refused_code() {
  if "$release" "$tmp/app.aab" "$tmp/notes" > /dev/null 2> "$tmp/err"; then fail "$case: succeeded"; fi
  grep -q "version code $1 is not above the highest on Play, $2" "$tmp/err" || fail "$case: did not name both numbers: $(cat "$tmp/err")"
  if requests | grep -Eq 'PUT|:commit'; then fail "$case: set the track or committed"; fi
  [ "$(requests | tail -1)" = "DELETE $app/edits/edit-1" ] || fail "$case: the edit was not deleted"
}

case="version code: equal to the one on the track (the 955894 case)"
codes_stub 955894 "" 955894
refused_code 955894 955894
echo "ok: $case"

case="version code: equal to a bundle that is on no track"
codes_stub "" "100,955894" 955894
refused_code 955894 955894
echo "ok: $case"

case="version code: lower than the track's"
codes_stub "955894,100" 7 955000
refused_code 955000 955894
echo "ok: $case"

case="version code: lower than a bundle's, above the track's"
codes_stub 10 200 150
refused_code 150 200
echo "ok: $case"

case="version code: higher than both is released"
codes_stub 955894 955000 955895
"$release" "$tmp/app.aab" "$tmp/notes" > "$tmp/out" || fail "$case: failed"
grep -q "version code 955895" "$tmp/out" || fail "$case: did not say the version code"
requests | grep -q ':commit' || fail "$case: did not commit"
echo "ok: $case"

case="version code: an empty track and no bundles is released"
codes_stub "" "" 1
"$release" "$tmp/app.aab" "$tmp/notes" > /dev/null || fail "$case: failed"
requests | grep -q ':commit' || fail "$case: did not commit"
echo "ok: $case"

case="a refused commit"
stub POST::commit
if "$release" "$tmp/app.aab" "$tmp/notes" > /dev/null 2>&1; then fail "$case: succeeded"; fi
[ "$(requests | tail -1)" = "DELETE $app/edits/edit-1" ] || fail "$case: the edit was not deleted"
echo "ok: $case"

case="notes over 500 characters"
stub
python3 -c 'print("é" * 501)' > "$tmp/long"
if "$release" "$tmp/app.aab" "$tmp/long" > /dev/null 2> "$tmp/err"; then fail "$case: succeeded"; fi
grep -q "501 characters" "$tmp/err" || fail "$case: did not say the length"
[ ! -s "$tmp/log" ] || fail "$case: asked Play"
python3 -c 'print("é" * 500)' > "$tmp/long"
"$release" "$tmp/app.aab" "$tmp/long" --dry-run > /dev/null || fail "500 characters: refused"
echo "ok: $case, and 500 taken"

case="empty notes"
stub
printf '  \n' > "$tmp/empty"
if "$release" "$tmp/app.aab" "$tmp/empty" > /dev/null 2>&1; then fail "$case: succeeded"; fi
[ ! -s "$tmp/log" ] || fail "$case: asked Play"
echo "ok: $case"

case="another track"
stub
PLAY_TRACK=beta "$release" "$tmp/app.aab" "$tmp/notes" > "$tmp/out" || fail "$case: failed"
expect_requests \
  "POST $app/edits" \
  "GET $app/edits/edit-1/tracks/beta" \
  "GET $app/edits/edit-1/bundles" \
  "POST /upload$app/edits/edit-1/bundles?uploadType=media" \
  "PUT $app/edits/edit-1/tracks/beta" \
  "POST $app/edits/edit-1:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW"
[ "$(jq -r 'select(.method == "PUT") | .body' "$tmp/log" | base64 -d | jq -r .track)" = beta ] || fail "$case: the track in the body"
grep -q "beta track" "$tmp/out" || fail "$case: did not say the track"
echo "ok: $case"

for track in production Beta ../internal 'a b' 1st; do
  case="the track '$track'"
  stub
  if PLAY_TRACK=$track "$release" "$tmp/app.aab" "$tmp/notes" > /dev/null 2> "$tmp/err"; then fail "$case: succeeded"; fi
  grep -q "error: the " "$tmp/err" || fail "$case: did not say why"
  [ ! -s "$tmp/log" ] || fail "$case: asked Play"
  echo "ok: $case is refused"
done

# every action the workflow uses is pinned by a 40-digit commit
case="the workflow's pins"
workflow=$here/../../.github/workflows/play-release.yml
uses=$(sed -n 's/^[[:space:]-]*uses:[[:space:]]*//p' "$workflow")
[ -n "$uses" ] || fail "$case: the workflow uses no action"
echo "$uses" | grep -Ev '^[^@ ]+@[0-9a-f]{40} # v[0-9][0-9.]*$' && fail "$case: an action not pinned by commit with its version" || true
echo "ok: $case"

# notes_sent <NOTES> <COMMIT_MESSAGE>: a dry run with the notes made from
# the environment (the workflow's way); the text the track is given is in $tmp/text
notes_sent() {
  stub
  NOTES=$1 COMMIT_MESSAGE=$2 "$release" "$tmp/app.aab" - --dry-run > /dev/null || fail "$case: failed"
  jq -r 'select(.method == "PUT") | .body' "$tmp/log" | base64 -d | jq -j '.releases[0].releaseNotes[0].text' > "$tmp/text"
}
want_text() { printf '%s' "$1" > "$tmp/want"; cmp "$tmp/want" "$tmp/text" || fail "$case: the notes were $(cat "$tmp/text")"; }
characters() { python3 -c 'import sys; print(len(open(sys.argv[1], encoding="utf-8").read()))' "$1"; }

case="notes: the first line of the commit message"
notes_sent '' "$(printf '  Add the thing  \n\nA body line\nAnother')"
want_text "Add the thing"
echo "ok: $case"

case="notes: given notes are taken whole, not cut at a line"
notes_sent "$(printf '\n  First\nSecond  \n')" "Ignored commit"
want_text "$(printf 'First\nSecond')"
echo "ok: $case"

case="notes: a commit's first line is cut to 500 characters"
long=$(python3 -c 'print("é" * 501)')
notes_sent '' "$long
body"
[ "$(characters "$tmp/text")" = 500 ] || fail "$case: not 500 characters"
want_text "$(python3 -c 'print("é" * 500, end="")')"
echo "ok: $case"

case="notes: given notes are cut to 500 characters"
notes_sent "$(python3 -c 'print("é" * 400 + "\n" + "x" * 400)')" ""
[ "$(characters "$tmp/text")" = 500 ] || fail "$case: not 500 characters"
echo "ok: $case"

case="notes: no notes and no commit message is refused before Play is asked"
stub
if NOTES= COMMIT_MESSAGE= "$release" "$tmp/app.aab" - > /dev/null 2>&1; then fail "$case: succeeded"; fi
[ ! -s "$tmp/log" ] || fail "$case: asked Play"
echo "ok: $case"

# the job's permissions are these two and no more (the job, not a
# workflow-wide block)
case="the workflow's permissions"
perms=$(awk '/^    permissions:/ {p = 1; next} p && /^      / {print; next} p {p = 0}' "$workflow")
[ "$perms" = "$(printf '      contents: read\n      id-token: write')" ] || fail "$case: the job's permissions are: $perms"
if grep -Eq '^permissions:' "$workflow"; then fail "$case: a permissions block outside the job"; fi
echo "ok: $case"

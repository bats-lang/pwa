#!/bin/sh
# Releases an AAB to one of Google Play's testing tracks (the internal
# track unless told otherwise; bats-lang/pwa#90, from quire#308), through
# the Play Developer API's edits: insert, upload the bundle, set the
# track to a completed release of its version code with these release
# notes, then commit (or, for a dry run, validate). Before anything is set,
# the new version code must be above every code Play already has (the
# track's releases and the edit's bundles, read from the API in the same
# edit before the upload: bats-lang/pwa#258, keyword: version-code). The release is named
# by Play, from the bundle's versionName. Committing with
# ERROR_IF_IN_REVIEW: a change in review is never cancelled by this one,
# which then fails instead. An edit that does not commit is deleted, so
# nothing is left half made. The production track is refused: that is a
# promotion of a tested release, in the Play Console.
#
# usage: scripts/play-release.sh <aab> <notes-file> [--dry-run]
#        scripts/play-release.sh <aab> - [--dry-run]
# With "-" for the notes file the notes are made from the environment
# (bats-lang/pwa#195; the workflow's notes input and the pushed commit's
# message): NOTES when it is not empty, taken whole, else the first line of
# COMMIT_MESSAGE; either way without the white space at either end and cut
# to Play's 500 characters at a whole character.
# env: NOTES and COMMIT_MESSAGE, only when the notes file is "-";
#      PLAY_ACCESS_TOKEN, an OAuth token with the androidpublisher scope;
#      PLAY_PACKAGE, the application id;
#      PLAY_TRACK, the track: internal (the default), alpha, beta or the
#      name of a custom closed track (lower case letters, digits, - and _);
#      PLAY_API, the API's root
#      (https://androidpublisher.googleapis.com unless a test stubs it)
set -eu
aab=$1 notes=$2
dry_run=${3:-}
track=${PLAY_TRACK:-internal}
case $track in
  production) echo "error: the production track is a promotion in the Play Console, not a release from here" >&2; exit 1 ;;
  ''|[!a-z]*|*[!a-z0-9_-]*) echo "error: the track '$track' is not a track name (lower case letters, digits, - and _)" >&2; exit 1 ;;
esac
api=${PLAY_API:-https://androidpublisher.googleapis.com}
app="$api/androidpublisher/v3/applications/$PLAY_PACKAGE"
upload="$api/upload/androidpublisher/v3/applications/$PLAY_PACKAGE"

body=$(mktemp)
edit=
cleanup() {
  status=$?
  if [ -n "$edit" ]; then
    curl -sS -o /dev/null -X DELETE -H "Authorization: Bearer $PLAY_ACCESS_TOKEN" "$app/edits/$edit" || true
  fi
  rm -f "$body" "$body.track" "$body.notes"
  exit $status
}
trap cleanup EXIT

# notes from the environment (see the usage); python3 is the tool that
# counts characters and cuts at one, as for the length below
if [ "$notes" = - ]; then
  python3 -c '
import os, sys
text = os.environ.get("NOTES", "")
if text:
    text = text.strip()
else:
    text = os.environ.get("COMMIT_MESSAGE", "").strip().split("\n")[0].strip()
with open(sys.argv[1], "w", encoding="utf-8") as out:
    out.write(text[:500])
' "$body.notes"
  notes=$body.notes
fi

# Play's "What's new" holds 500 characters a language (the notes are
# taken without the white space at either end)
length=$(python3 -c 'import sys; print(len(open(sys.argv[1], encoding="utf-8").read().strip()))' "$notes")
if [ "$length" -eq 0 ]; then
  echo "error: the release notes are empty" >&2
  exit 1
fi
if [ "$length" -gt 500 ]; then
  echo "error: the release notes are $length characters; Play takes at most 500" >&2
  exit 1
fi
[ -s "$aab" ] || { echo "error: no AAB at $aab" >&2; exit 1; }

# call <what> <curl arguments>: the answer in $body, a failure said with it
call() {
  what=$1
  shift
  code=$(curl -sS -o "$body" -w '%{http_code}' -H "Authorization: Bearer $PLAY_ACCESS_TOKEN" "$@")
  case $code in
    2??) ;;
    *) echo "error: $what: HTTP $code" >&2; cat "$body" >&2; echo >&2; exit 1 ;;
  esac
}

call "create the edit" -X POST -H 'Content-Type: application/json' -d '{}' "$app/edits"
edit=$(jq -r .id "$body")
echo "edit $edit"

# the codes Play already has, read in this edit before the upload; the
# track's are strings and the bundles' numbers, and each may be empty
call "read the $track track" -X GET "$app/edits/$edit/tracks/$track"
on_track=$(jq -r '[.releases[]?.versionCodes[]? | tonumber] | max // empty' "$body")
call "list the bundles" -X GET "$app/edits/$edit/bundles"
in_bundles=$(jq -r '[.bundles[]?.versionCode | tonumber] | max // empty' "$body")
highest=
for code in "$on_track" "$in_bundles"; do
  if [ -n "$code" ] && { [ -z "$highest" ] || [ "$code" -gt "$highest" ]; }; then highest=$code; fi
done

call "upload the bundle" -X POST -H 'Content-Type: application/octet-stream' \
  --data-binary "@$aab" "$upload/edits/$edit/bundles?uploadType=media"
version_code=$(jq -r .versionCode "$body")
echo "bundle uploaded: version code $version_code"

# Play names the code in its answer to the upload (it is in the bundle's
# manifest, a protobuf), so the comparison is here, before the track is set
if [ -n "$highest" ] && [ "$version_code" -le "$highest" ]; then
  echo "error: the new version code $version_code is not above the highest on Play, $highest (track $track: ${on_track:-none}, bundles: ${in_bundles:-none})" >&2
  exit 1
fi

jq -n --arg track "$track" --arg code "$version_code" --rawfile notes "$notes" '{
  track: $track,
  releases: [{
    versionCodes: [$code],
    status: "completed",
    releaseNotes: [{language: "en-US", text: ($notes | sub("^\\s+"; "") | sub("\\s+$"; ""))}]
  }]
}' > "$body.track"
call "set the $track track" -X PUT -H 'Content-Type: application/json' \
  --data-binary "@$body.track" "$app/edits/$edit/tracks/$track"

if [ "$dry_run" = --dry-run ]; then
  call "validate the edit" -X POST "$app/edits/$edit:validate"
  echo "dry run: the edit is valid; it is deleted, not committed"
else
  call "commit the edit" -X POST "$app/edits/$edit:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW"
  edit=
  echo "released to the $track track: version code $version_code"
fi

#!/bin/sh
# The Android SDK pins' part of the daily relock (bats-lang/pwa#185, area: android-relock).
# Shell because the tool is bats and bats has no HTTP client: this fetches Google's two
# repository XML files and the Last-Modified of each archive a pin may move to, as text files,
# builds the tool and runs `android-sdk-pins repin` on them. It reads no XML itself: the one
# text match below only lists the <url> lines of one package's <remotePackage> blocks, the
# tool reads the feeds. Detail: .claude/rules/android-relock.md
#
# usage: relock.sh <pins-directory>     (run in the repository's root by relock-pins.yml)
# environment: REPIN_RECORDS      the file the tool's move records are appended to (required)
#              BATS_REPOSITORY    the package repository the tool is built against
#              ANDROID_SDK_PINS_BIN       a built tool: nothing is built (a test's)
#              ANDROID_SDK_FEEDS_URL      where the two feeds are (a test's; Google's by default)
#              ANDROID_SDK_ARCHIVES_URL   where the archives are, in place of each pin's URL
#                                         directory (a test's)
set -eu
pins=${1:?usage: relock.sh <pins-directory>}
: "${REPIN_RECORDS:?REPIN_RECORDS names the file the move records are appended to}"
feeds_url=${ANDROID_SDK_FEEDS_URL:-https://dl.google.com/android/repository}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/feeds"

# The tool, built in a copy so the checkout holds no build output
if [ -n "${ANDROID_SDK_PINS_BIN:-}" ]; then
  tool=$ANDROID_SDK_PINS_BIN
else
  cp -R "$pins" "$work/tool"
  (cd "$work/tool" && bats build --repository "${BATS_REPOSITORY:?BATS_REPOSITORY names the package repository}")
  tool=$work/tool/dist/debug/android-sdk-pins
fi

curl -fsS --retry 3 --max-time 300 -o "$work/feeds/repository2-1.xml" "$feeds_url/repository2-1.xml"
curl -fsS --retry 3 --max-time 300 -o "$work/feeds/sys-img2-1.xml" "$feeds_url/sys-img/android/sys-img2-1.xml"

# The whole days since the Last-Modified of <url-directory>/<name>, in <name>.age of the feeds'
# directory; nothing is written when the server gives none (the tool then says which age it lacks)
age_of() {
  last_modified=$(curl -fsSI --retry 3 --max-time 120 "$1/$2" | tr -d '\r' \
    | awk 'tolower($1) == "last-modified:" { sub(/^[^:]*: */, ""); print; exit }') || return 0
  [ -n "$last_modified" ] || return 0
  then_seconds=$(date -u -d "$last_modified" +%s) || return 0
  now_seconds=$(date -u +%s)
  days=$(( (now_seconds - then_seconds) / 86400 ))
  [ "$days" -ge 0 ] || days=0
  echo "$days" > "$work/feeds/$2.age"
}

# For each pin: the archive it names and every archive the feeds list for its package
while read -r name url rest; do
  case "$name" in ''|'#'*) continue ;; esac
  package=$(grep -o 'path="[^"]*"' "$pins/$name.xml" | head -n 1 | cut -d'"' -f2)
  [ -n "$package" ] || { echo "relock.sh: $pins/$name.xml has no package path" >&2; exit 1; }
  directory=${ANDROID_SDK_ARCHIVES_URL:-${url%/*}}
  { echo "${url##*/}"
    for feed in "$work/feeds/repository2-1.xml" "$work/feeds/sys-img2-1.xml"; do
      awk -v open="<remotePackage path=\"$package\">" '
        index($0, open) { inside = 1 }
        inside {
          line = $0
          while (match(line, /<url>[^<]*<\/url>/)) {
            print substr(line, RSTART + 5, RLENGTH - 11)
            line = substr(line, RSTART + RLENGTH)
          }
        }
        index($0, "</remotePackage>") { inside = 0 }' "$feed"
    done; } | sort -u > "$work/names"
  while read -r archive; do
    case "$archive" in ''|*[!A-Za-z0-9._-]*) continue ;; esac
    age_of "$directory" "$archive"
  done < "$work/names"
done < "$pins/pins.txt"

(cd "$pins" && "$tool" repin "$work/feeds") >> "$REPIN_RECORDS"

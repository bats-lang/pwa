#!/bin/sh
# Prints the SHA-1 and SHA-256 fingerprints of the certificate of an
# alias in a keystore (bats-lang/pwa#96, from quire#200), and, when told
# Play's app signing SHA-1, fails if it is the key's own. Play re-signs
# what is uploaded with its own key, so an app installed from Play carries
# Play's certificate, not the upload key's: an Android OAuth client
# registered with the upload key's SHA-1 signs in on a sideloaded APK and
# fails only on the installed app.
#
# usage: scripts/key-fingerprints.sh <keystore>
# env: KEYSTORE_PASSWORD and KEY_ALIAS, the keystore's (the password is
#      handed to keytool by its name, -storepass:env, so it is on no
#      command line and is never printed);
#      PLAY_SIGNING_SHA1, optional: Play Console, Protected with Play
#      (App integrity), Play app signing, App signing key certificate.
#      Fails unless it is a SHA-1 fingerprint (20 bytes of hex, colon
#      separated, either case) other than the key's.
#      With GITHUB_STEP_SUMMARY set, the fingerprints are added to it.
# The fingerprints are public (every signed APK carries them).
set -eu
keystore=${1:?usage: key-fingerprints.sh <keystore>}
: "${KEY_ALIAS:?KEY_ALIAS is not set}"
: "${KEYSTORE_PASSWORD:?KEYSTORE_PASSWORD is not set}"
export KEYSTORE_PASSWORD

# keytool fails on a wrong password or alias, saying so
listing=$(keytool -list -v -keystore "$keystore" -storepass:env KEYSTORE_PASSWORD -alias "$KEY_ALIAS")
field() { printf '%s\n' "$listing" | sed -n "s/^[[:space:]]*$1: *//p" | head -1; }
sha1=$(field SHA1)
sha256=$(field SHA256)
hex() { printf '%s' "$1" | grep -Eqx "([0-9A-F]{2}:){$2}[0-9A-F]{2}"; }
hex "$sha1" 19 || { echo "error: no SHA-1 fingerprint for the alias in the keystore" >&2; exit 1; }
hex "$sha256" 31 || { echo "error: no SHA-256 fingerprint for the alias in the keystore" >&2; exit 1; }

echo "Upload key SHA-1: $sha1"
echo "Upload key SHA-256: $sha256"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Android signing key (upload key)"
    echo
    echo "| | |"
    echo "|---|---|"
    echo "| SHA-1 | \`$sha1\` |"
    echo "| SHA-256 | \`$sha256\` |"
    echo
    echo "Apps installed from Google Play carry Play's app signing key instead; its SHA-1 is in Play Console, Protected with Play, Play app signing."
  } >> "$GITHUB_STEP_SUMMARY"
fi

play=${PLAY_SIGNING_SHA1:-}
if [ -n "$play" ]; then
  play=$(printf '%s' "$play" | tr 'a-f' 'A-F')
  hex "$play" 19 || { echo "error: play-signing-sha1 is not a SHA-1 fingerprint (AA:BB:... , 20 bytes)" >&2; exit 1; }
  if [ "$play" = "$sha1" ]; then
    echo "error: play-signing-sha1 is the upload key's SHA-1, not Play's app signing key's" >&2
    exit 1
  fi
  echo "Play app signing SHA-1: $play (not the upload key's)"
fi

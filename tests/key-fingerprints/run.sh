#!/bin/sh
# scripts/key-fingerprints.sh (bats-lang/pwa#96) on keystores made here
# with keytool: the fingerprints printed are the certificate's own (read
# a second way, from the exported certificate with openssl), the
# password reaches no output, a Play SHA-1 that is the key's own is
# refused (in either case), a different one is accepted, a malformed one
# is refused, a wrong password or alias fails, and with no Play SHA-1
# nothing is checked. Run from anywhere.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=$here/../../scripts/key-fingerprints.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

export KEYSTORE_PASSWORD=s3cretpassw0rd KEY_ALIAS=upload
unset PLAY_SIGNING_SHA1 GITHUB_STEP_SUMMARY
keytool -genkeypair -keystore "$tmp/a.jks" -storepass "$KEYSTORE_PASSWORD" -keypass "$KEYSTORE_PASSWORD" \
  -alias upload -dname "CN=Test" -keyalg RSA -keysize 2048 -validity 30 >/dev/null 2>&1
keytool -genkeypair -keystore "$tmp/b.jks" -storepass "$KEYSTORE_PASSWORD" -keypass "$KEYSTORE_PASSWORD" \
  -alias upload -dname "CN=Other" -keyalg RSA -keysize 2048 -validity 30 >/dev/null 2>&1

# run <name> <keystore>: output in $tmp/out, status in $status
run() { status=0; sh "$script" "$2" > "$tmp/out" 2>&1 || status=$?; }

run "plain" "$tmp/a.jks"
[ $status -eq 0 ] || fail "plain: exit $status: $(cat "$tmp/out")"
sha1=$(sed -n 's/^Upload key SHA-1: //p' "$tmp/out")
sha256=$(sed -n 's/^Upload key SHA-256: //p' "$tmp/out")
printf '%s' "$sha1" | grep -Eqx '([0-9A-F]{2}:){19}[0-9A-F]{2}' || fail "plain: SHA-1 '$sha1' is not 20 bytes"
printf '%s' "$sha256" | grep -Eqx '([0-9A-F]{2}:){31}[0-9A-F]{2}' || fail "plain: SHA-256 '$sha256' is not 32 bytes"
grep -q "$KEYSTORE_PASSWORD" "$tmp/out" && fail "plain: the password is in the output"

# the same digests from the certificate, computed by openssl
keytool -exportcert -keystore "$tmp/a.jks" -storepass "$KEYSTORE_PASSWORD" -alias upload -file "$tmp/a.der" >/dev/null 2>&1
for algo in sha1 sha256; do
  want=$(openssl dgst -"$algo" -hex "$tmp/a.der" | sed 's/^.*= *//' | tr 'a-f' 'A-F' | sed 's/../&:/g; s/:$//')
  eval got=\$$algo
  [ "$got" = "$want" ] || fail "plain: $algo '$got' is not the certificate's '$want'"
done

# another key's fingerprint differs, and is the one that is accepted
run "other" "$tmp/b.jks"
other=$(sed -n 's/^Upload key SHA-1: //p' "$tmp/out")
[ "$other" != "$sha1" ] || fail "two keys with one SHA-1"

PLAY_SIGNING_SHA1=$sha1 run "same" "$tmp/a.jks"
[ $status -ne 0 ] || fail "the upload key's SHA-1 was accepted"
grep -q "upload key's SHA-1" "$tmp/out" || fail "same: the refusal does not say why: $(cat "$tmp/out")"
lower=$(printf '%s' "$sha1" | tr 'A-F' 'a-f')
PLAY_SIGNING_SHA1=$lower run "same, lower case" "$tmp/a.jks"
[ $status -ne 0 ] || fail "the upload key's SHA-1 in lower case was accepted"

PLAY_SIGNING_SHA1=$other run "different" "$tmp/a.jks"
[ $status -eq 0 ] || fail "a different SHA-1 was refused: $(cat "$tmp/out")"
PLAY_SIGNING_SHA1=$(printf '%s' "$other" | tr 'A-F' 'a-f') run "different, lower case" "$tmp/a.jks"
[ $status -eq 0 ] || fail "a different SHA-1 in lower case was refused: $(cat "$tmp/out")"

# not a SHA-1 fingerprint: no colons, too short, the SHA-256, not hex
nl='
'
for bad in "$(printf '%s' "$other" | tr -d ':')" "${other%:*}" "$sha256" "ZZ:${other#??:}" \
  "$sha1${nl}junk" "junk${nl}$sha1" "$other${nl}junk" "junk${nl}$other" "$sha1${nl}" "${nl}$sha1"; do
  PLAY_SIGNING_SHA1=$bad run "malformed" "$tmp/a.jks"
  [ $status -ne 0 ] || fail "malformed '$bad' was accepted"
  grep -q "not a SHA-1 fingerprint" "$tmp/out" || fail "malformed '$bad': wrong refusal: $(cat "$tmp/out")"
  ! grep -q junk "$tmp/out" || fail "malformed: the value was printed"
done

# a wrong password or alias fails, and the password is not printed
KEYSTORE_PASSWORD=wrong-password-x run "wrong password" "$tmp/a.jks"
[ $status -ne 0 ] || fail "a wrong password was accepted"
grep -qi "password was incorrect" "$tmp/out" || fail "wrong password: keytool's message is not shown: $(cat "$tmp/out")"
grep -q "wrong-password-x" "$tmp/out" && fail "wrong password: printed"
KEY_ALIAS=nothing run "wrong alias" "$tmp/a.jks"
[ $status -ne 0 ] || fail "a wrong alias was accepted"
grep -qi "does not exist" "$tmp/out" || fail "wrong alias: keytool's message is not shown: $(cat "$tmp/out")"

# the job summary
GITHUB_STEP_SUMMARY=$tmp/summary run "summary" "$tmp/a.jks"
grep -q "$sha1" "$tmp/summary" && grep -q "$sha256" "$tmp/summary" || fail "the summary lacks the fingerprints"
grep -q "$KEYSTORE_PASSWORD" "$tmp/summary" && fail "the password is in the summary"

# the workflow runs it
workflow=$here/../../.github/workflows/android.yml
python3 - "$workflow" <<'PY' || fail "android.yml's fingerprint steps are not wired as they should be"
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["jobs"]["build-android"]["steps"]
by = {s.get("name"): s for s in steps}
run = by["Signing key fingerprints"]
assert "if" in run and "ANDROID_KEYSTORE" in run["if"] and "pwa-ref" in run["if"], run
assert run["env"]["PLAY_SIGNING_SHA1"] == "${{ inputs.play-signing-sha1 }}", run
assert run["env"]["KEYSTORE_PASSWORD"] == "${{ secrets.KEYSTORE_PASSWORD }}", run
assert run["env"]["KEY_ALIAS"] == "${{ secrets.KEY_ALIAS }}", run
assert "key-fingerprints.sh" in run["run"] and "inputs." not in run["run"], run
get = by["Get the fingerprint script"]
assert get["with"]["ref"] == "${{ inputs.pwa-ref }}" and "pwa-ref" in get["if"], get
assert "${{" not in by["Check pwa-ref"]["run"], "pwa-ref is spliced into a script"
assert by["Check pwa-ref"]["env"]["PWA_REF"] == "${{ inputs.pwa-ref }}"
names = [s.get("name") for s in steps]
assert names.index("Check pwa-ref") < names.index("Get the fingerprint script") < names.index("Signing key fingerprints")
for n in ("A Play signing SHA-1 needs pwa-ref", "A Play signing SHA-1 needs a signing key"):
    assert "inputs.play-signing-sha1 != ''" in by[n]["if"], n
PY

echo "key-fingerprints: ok"

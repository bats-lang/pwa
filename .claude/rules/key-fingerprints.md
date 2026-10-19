---
paths:
  - scripts/key-fingerprints.sh
  - tests/key-fingerprints/**
  - .github/workflows/android.yml
---

# The signing key's fingerprints (pwa#96, quire#623)

`android.yml` printed nothing of the key it signs with, and an app's own
workflow (quire's `sync-identity.yml`) decoded the keystore again to print
the upload key's SHA-1 and SHA-256 and to refuse a registered Play app
signing SHA-1 that is the upload key's (quire#200: the Android OAuth
client was registered with the upload key's certificate, which an app
installed from Play, signed by Play's own key, does not carry).
`scripts/key-fingerprints.sh` does both for every app; android.yml's steps
call it when `pwa-ref` is given (the script is taken from that commit, as
play-release.yml's is) and `play-signing-sha1` adds the refusal.

* **Process, not a capability.** It reads the keystore android.yml already
  decodes and signs with; nothing pwa generates changes. Without the new
  inputs the workflow does what it did.
* **No secret in output.** The password reaches keytool as
  `-storepass:env` (on no command line; the decode step's own keytool call
  uses it too); keytool's listing is never
  printed, only the two fingerprints, which every signed APK carries.
* **`pwa-ref` is optional so existing callers are unchanged.** Taking the
  script from the default branch instead would be an unpinned input.
  `pwa-ref` must be 40 lower case hex digits (checked before the checkout).
  A `play-signing-sha1` with no `pwa-ref` or no signing key fails rather
  than skip a check that was asked for.
* `tests/key-fingerprints/run.sh` (a step of `check`) makes keystores with
  keytool, compares the printed digests with openssl's of the exported
  certificate, and checks the refusals and acceptances. The workflow's
  steps need an app's secrets and run in an app's job.

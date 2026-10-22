---
paths:
  - src/lib.bats
  - .github/workflows/android.yml
  - tests/android/**
---

# The Android smoke test

* The Android smoke test runs on AOSP's emulator image, without Google
  Play services: on a fresh boot they restart their process at no set
  time, and Android kills every app holding a connection to one of
  their providers, as Android System WebView does to their FontsProvider
  (quire#220). The system image is cached between runs.
* The SDK packages the smoke test installs (platform-tools, platforms;android-34,
  the emulator, the system image) are deliberately unpinned: the exception is
  written above the install step in `android.yml`, with its reason
  (bats-lang/pwa#130). sdkmanager has no revision syntax for them; the
  emulator action's `emulator-build` pin downloads with no checksum and no
  retry; Google's feeds keep only the newest system image and two emulator
  revisions. A pin needs a checksummed download of each package from the feed,
  tested in the smoke test, in a pull request of its own.

# The pnpm download of the Android build (pwa#158)

* pnpm 12's corepack entry downloads its native binary from the registry on
  first use, with a fixed 30 s timeout for the metadata and no retry (get-pnpm's
  `registry.js`); 9 of 12 runs of quire's `android / build-android` failed on
  it. `fetch-pnpm.sh` (written beside `build-android.sh`, which sources it)
  runs pnpm once, again when the output says the network failed (the same
  family of words as the e2e-setup action's `retry.sh`), 3 tries and a pause
  that doubles, and exits non-zero naming the URL pnpm named. Shell, since
  it is a generated script that runs in an app's checkout with no bats and
  no pwa (`retry.sh` cannot be called from there); the avenue tried first
  was `retry.sh`, which is a file of this repository and not of the app's.
* Pins: the wrapper's sha512 in the `corepack pnpm@12.9.1+sha512.<hex>`
  spec (corepack refuses another tarball), and the binary's sha256 for
  linux-x64, linux-arm64, darwin-x64 and darwin-arm64 (glibc); any other host
  says so and keeps the registry-signature check get-pnpm does. Both move
  with the version, from `npm pack pnpm@<v>` and `npm pack @pnpm/exe.<target>@<v>`
  (the binary is `package/pnpm`). `tests/android/pnpm.sh` takes the real
  tarballs from npm and fails if a pin is not theirs.
* The cache `~/.cache/node/corepack` is checked too: a binary that is not the
  pinned one is removed and the build fails.

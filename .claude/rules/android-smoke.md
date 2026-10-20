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

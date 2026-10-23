---
paths:
  - src/lib.bats
  - .github/workflows/android.yml
  - tests/android/**
  - tests/android-smoke-dom/**
  - tools/android-sdk-pins/**
  - tests/android-sdk-pins/**
---

# The Android smoke test

* The Android smoke test runs on AOSP's emulator image, without Google
  Play services: on a fresh boot they restart their process at no set
  time, and Android kills every app holding a connection to one of
  their providers, as Android System WebView does to their FontsProvider
  (quire#220). The system image is cached between runs.
* The SDK packages the smoke test runs on (platform-tools, platforms;android-34,
  the emulator, the system image) are pinned by revision, each with the SHA-1
  of its archive in Google's repository XML (bats-lang/pwa#137).
  `tools/android-sdk-pins` (a bats binary: no shell of ours) installs them
  from `pins.txt`: a line is `<name> <url> <sha1> <unzip-into> <package-dir>`
  and `<name>.xml` is the `package.xml` sdkmanager writes for that revision.
  A package whose `package.xml` is those bytes is left alone; else the zip is
  downloaded with curl, its SHA-1 (sha1sum) must be the pin's (a mismatch is
  not installed and is tried again, `ANDROID_SDK_PINS_ATTEMPTS`, default 3,
  with a pause that doubles from `ANDROID_SDK_PINS_PAUSE_S`, default 15; then
  the run fails naming the package), the package directory is replaced, and
  `<name>.xml` copied in. sdkmanager has no revision syntax for these packages
  and the emulator action's `emulator-build` downloads with no checksum and no
  retry, so the archive is installed as Google's repository manager does:
  unpacked into the SDK, with the `package.xml` beside it, which makes
  sdkmanager see the revision as installed.
* The emulator action runs sdkmanager for the same packages after the tool: a
  no-op while the pins are the newest in the stable channel, and an upgrade
  when Google has published newer ones. So `android.yml` runs the tool a second
  time in the action's `pre-emulator-launch-script`, which puts the pins back
  before the emulator starts (the AVD is made before that, and refers to the
  image by its directory, `image.sysdir.1=system-images/android-34/default/x86_64/`
  in its `config.ini`, which the tool keeps and replaces the contents of; the
  emulator reads the kernel, ramdisk and system image from that directory at
  boot). The tool is built in the job `sdk-pins-tool`
  (the bats setup action, called by commit, at pwa's own `.github/bats-version`)
  while the app builds, and handed to the smoke test as an artifact. The system
  image's cache key ends with the SHA-256 of `pins.txt`, which the tool prints
  (`android-sdk-pins key`, run in the step "Name the system image's cache"; not
  `hashFiles`, a GitHub expression no test can run), so a pin that moves is a new
  key and an old key never serves a changed image (pwa#138).
* Moving a pin is a pull request that runs the same CI, never a floating
  install: take the new revision's `<checksum>`, `<url>` and `<display-name>` from
  `https://dl.google.com/android/repository/repository2-1.xml` (the system image:
  `.../sys-img/android/sys-img2-1.xml`; the sdkmanager default is the newest
  of the stable channel, `channel-0`, and for `platforms;android-34` the highest
  revision), edit its line in `pins.txt`, and replace `<name>.xml` with the
  `package.xml` sdkmanager writes for it (`sdkmanager --sdk_root=<empty dir>
  --install '<package>' --channel=0`, copy `<dir>/package.xml`). Moving them with the
  relock is pwa#173. When Google removes an archive the pin names, the
  smoke test's job fails in the step "Install the emulator's SDK packages at their
  pins" with `curl: (22) ... 404` and `the download failed`, then `no download that
  matches the pinned SHA-1 could be had: refused`; the fix is that pull request. A
  replaced archive at the same URL fails with `is not the pinned one: its SHA-1
  differs from the pin`.
* `tests/android-sdk-pins/check.sh` (the `check` job) runs the tool against small
  packages and a stand-in for Google's server: the pinned download installed
  (its first response cut short), a package already as pinned left alone with
  nothing downloaded, a download with a bad SHA-1 refused on every try with the
  package that was there kept, a package at another revision replaced (the old
  files gone, the new in place, `package.xml` the pinned one), the lines
  installed in order and stopping at the first that fails, a 404, and a pins
  file that is not usable, and the digest `key` prints (the SHA-256 of
  `pins.txt`; another when a SHA-1, a URL or a line of the pins changes; none
  without `pins.txt`). The
  real packages are installed by the smoke test itself, in the `android` job.
* An image in the cache or an SDK of the runner that is not the pinned revision
  is replaced; one that is cannot be told apart by its files, only by its
  `package.xml`, which the tool compares byte for byte.

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

# The page's DOM, kept when the smoke test's wait gives up (pwa#166)

* The dump (`ui.xml`, the accessibility tree) and the screenshot (the pixels) can
  disagree about a page: the WebView's tree may lack text that is on the screen.
  Neither shows the page's own state, so when `shown` gives up, `smoke-test.sh`
  also keeps the page's DOM, `dom.html`, beside them in the artifact
  `android-smoke-test`. A fix for a missing text starts from which of the three
  has it: the DOM, the tree or the pixels.
* `keep_dom` (in the script `build_smoke_test_script` writes) reads the app's pid,
  finds `webview_devtools_remote_<pid>` in `/proc/net/unix`, makes `adb forward
  tcp:0 localabstract:<it>` (a port the host picks, so it cannot meet a forward the
  failure evidence in `android.yml` makes on 9222), asks each page of
  `/json` for `document.documentElement.outerHTML` over the DevTools protocol
  (`Runtime.evaluate`) and writes them, each after a line `<!-- page: type url -->`.
  A message over 64 MiB is not read. It removes the forward.
* It says what it could not do in `dom.html` itself: `No DevTools socket (app pid
  N)`, or `DevTools did not answer` (60 s at most). A run that gives up twice keeps
  the last, as `ui.xml` does.
* Shell and python3, since the script runs on the emulator's host with adb and no
  bats, in an app's checkout (bats has no WebSocket client and the script no bats;
  `tests/android/activity.sh` is the precedent for a test of generated shell). It
  runs on the CI host only and reads the page: no JS of pwa's is added to the page
  or the activity, and nothing the app runs changes.
* `tests/android-smoke-dom/check.sh <smoke-test.sh>` (a step of `check`) runs the
  script against a stand-in `adb` and a stand-in DevTools endpoint (`server.py`: a
  page and a worker listed, a console event before the answer, the document in two
  frames of more than 65535 bytes with a ping between): a text never shown keeps
  `dom.html` with the `bats-root` element next to the other three files; a text
  shown keeps none and makes no forward; no socket and a silent page are said in
  the file, and the forward is removed after silence.

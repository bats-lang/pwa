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
  --install '<package>' --channel=0`, copy `<dir>/package.xml`). `android-sdk-pins repin`
  does that by program (below). When Google removes an archive the pin names, the
  smoke test's job fails in the step "Install the emulator's SDK packages at their
  pins" with `curl: (22) ... 404` and `the download failed`, then `no download that
  matches the pinned SHA-1 could be had: refused`; the fix is that pull request. A
  replaced archive at the same URL fails with `is not the pinned one: its SHA-1
  differs from the pin`.
* `android-sdk-pins repin <feed-directory>`, run in the directory of `pins.txt`, moves
  the pins to the newest stable revision in Google's two repository XML files, which
  the caller has put in `<feed-directory>` as `repository2-1.xml` and `sys-img2-1.xml`
  (the tool makes no network call). Beside them the caller writes `<archive file
  name>.age`, the whole days since the archive's `Last-Modified`, for the pinned
  archive of each package and for the one it may move to (the repository XML has no
  date). The XML is read as text, never parsed as a tree: a package is the
  `<remotePackage path="P">` blocks of its path (a block with another attribute,
  `obsolete="true"`, is not one); the stable channel is the `<channel id="X">stable`
  whose id the block's `<channelRef ref="X"/>` names (the ids are Google's to number;
  a revision on dev, beta or canary is not a newer pin); the latest revision is the
  greatest major, minor, micro (absent is 0) whatever the order of the blocks; its
  archive is the first `<archive>` with `host-os` linux or none, `host-bits` 64 or
  none and no `host-arch`; its `<checksum>` must be 40 lower case hex digits and its
  `<url>` letters, digits, dot, minus, underscore; the URL is the pinned URL's
  directory and that name. A moved package gets its `pins.txt` line (only the URL and
  the SHA-1 change; every other byte of the file is kept) and its `<name>.xml` with
  the `<revision>` written as sdkmanager writes it and the `<display-name>` of the
  feed, the rest of the file as it was (the package's own type details are not
  rewritten: for a platform, the block with the same `<extension-level>` when both
  have one). Each package prints a record, tab separated: `android-sdk`, name, old and
  new revision, age, `moved` or `current`: the format of repository-prototype's
  `tools/repin`, whose `kind` word is the first column. Exit 0 when every package was
  examined; 1 when one cannot be (a checksum that is not a SHA-1, no Linux archive, no
  stable channel, a missing `.age`, `<name>.xml` or feed), said on stderr; 2 when
  `pins.txt` is not usable. After a 1 the files already written are the caller's to
  discard. `tests/android-sdk-pins/repin.sh` runs it against fixtures of the feeds
  (`tests/android-sdk-pins/repin/`: pins already the newest, newer revisions only on
  another channel or obsolete, a platform of another extension level, a newer stable
  one in any block order, every pin newer with another stable channel id) and the
  unusable cases.
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

# "On the screen" is the page's answer, not the accessibility tree's (pwa#201)

* `shown` (in `smoke-test.sh`) used to poll `uiautomator dump` for the text. Each dump
  opens an accessibility connection for about a second, and Chromium's WebView
  builds its tree only while one is connected; on a slow emulator all 64 dumps of
  a run (run 40095843379, job 120880157426) came back without the text of a page
  that had loaded and drawn it (`dom.html` and `screenshot.png` of that run had
  it). The check was a race with the tree.
* It now asks the page, over the DevTools socket `keep_dom` already uses
  (`devtools_eval`), every 2 s: `document.visibilityState === "visible" &&
  document.body !== null && document.body.innerText.indexOf(<text>) >= 0` (the
  `SHOWN` expression). `innerText` is the text as laid out (not hidden by CSS) and
  `visible` says the page is the one in front, which is what "on the screen" meant;
  the screenshot, taken at the end as before, is the evidence that it was drawn.
  Found is the answer `true`. It reads only; nothing in the page or the app changes.
* Research (what comparable suites decide on): Appium's WebView automation switches
  to the WEBVIEW context, which is chromedriver over the same DevTools protocol,
  and reads the page (`getPageSource`, `execute`) rather than the native tree;
  Playwright's Android support (`device.webView()`) drives a WebView's pages over
  DevTools as well. Both ask the page, as here. Neither was run for this change.
* The wait is 60 polls or `SMOKE_WAIT_S` seconds (default 120, "two minutes"; the
  test sets it to seconds), whichever ends first: a silent page takes 15 s a poll.
  On giving up, `ui.xml` (one dump, for evidence), `dom.html`, `shown-answer.txt` (the
  last answer) and the screenshot are kept, and the failure line says how many polls
  were made, when the last was and what it answered.
* `tests/android-smoke-dom/check.sh` plays it (`server.py` answers the page's
  question from its document): a dump that never holds the text while the page has
  it passes, with no `uiautomator` call; a dump that holds a text the page lacks,
  and a page that has the text but is not visible, fail.
* **Overlap, not an in-place change (pwa#202).** The new text does not fit the
  published `n + 15000` of `build_smoke_test_script_font_scale` (head 10400 to about
  10900 bytes), and a published bound is part of the type a dependent compiles
  against. So the type and the text of the two published forms are unchanged
  (`build_smoke_test_script`, `n + 12000`; `build_smoke_test_script_font_scale`,
  `n + 15000`: both still poll `uiautomator dump`, byte for byte the script of main
  before pwa#201), and the fix is the new form beside them,
  `build_smoke_test_script_font_scale_devtools` (`n + 16000`), which `create_android`
  writes and so which every app build's `smoke-test.sh` is. The script is built from
  pieces (`_smoke_head_a`, `_smoke_shown_dump` or `_smoke_shown_devtools`,
  `_smoke_head_b`, the font scale step, `_smoke_tail_a`, `_smoke_never_dump` or
  `_smoke_never_devtools`, `_smoke_tail_b`) each with its own bound, so the old forms
  keep their proof. `tests/dynamic/smoke-compat` calls both old forms and compares
  their text with `expected`, so an edit cannot drop them. The old
  `font_scale` is removed by bats-lang/pwa#203, `build_smoke_test_script` by #189.
  `build_main_activity` is not changed (11500). No dependent calls either form
  directly (quire's `gen-pwa` calls `create_android_locked`).

# The system font scale on the emulator (pwa#154, quire#412)

* Chromium cannot stand in for the Android WebView's text size (quire's
  `font-scale.spec.js` plays `text-size-adjust` instead), so the real WebView is
  played here. With the text shown, `smoke-test.sh` sets `settings put system
  font_scale` to 1.0, 1.3 and 2.0 and back to 1.0, and at each reads the page
  through `devtools_eval` (the DevTools reader of `keep_dom`, now taking the
  expression): the height of the first line box of the smoke text (a `Range` over
  its text node, as the page lays it out) and the window's and the page's width.
  It fails unless, at 1.3 and 2.0, that line is the 1.0 line times the scale
  within 10%, the page is no wider than the window (`scrollWidth`) and the text
  lies inside the window. That is the claim "the shell sets no `textZoom`, so the
  system scale reaches the page": a shell that calls `setTextZoom(100)` keeps the
  line at its 1.0 height. The probe reads and measures only; the page, the
  activity and the app are not changed.
* The activity is recreated by a font scale (see the file hand-over steps), so each
  scale is probed again until the answer is right, 15 tries 2 s apart: a page that
  is still loading, or still at the old scale, is not a failure, the last answer is.
* `build_smoke_test_script_font_scale` is the form `create_android` writes;
  `build_smoke_test_script` stays beside it without the step (the head and tail
  are shared), called by `tests/dynamic/smoke-compat`, whose `expected` is its
  text. `tests/android-smoke-dom/check.sh` plays the step against the stand-in
  `adb` (it records the scale set) and `server.py`, whose probe answers a line
  20 px times the scale: passes; the line staying at 20 px (a shell with
  `textZoom`), a page wider than the window, text past the window's edge and a
  silent page each fail with their reason.

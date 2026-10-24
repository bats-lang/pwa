---
paths:
  - tools/android-sdk-pins/relock.sh
  - tests/android-relock/**
  - .github/workflows/relock.yml
  - .github/workflows/relock-android-test.yml
---

# The relock moves the Android SDK pins (pwa#185, piece 3 of 3 of pwa#173)

Pins move only from the relock (repository-prototype#392), and the four pins of
`tools/android-sdk-pins/pins.txt` are the relock's too: `relock.yml` gives the shared
`relock-pins.yml` (called by commit, `1f551f7`, repository-prototype#420's PR 424) a
`repin-command` and `repin-paths`.

* **The command** is `sh tools/android-sdk-pins/relock.sh tools/android-sdk-pins`, run by the
  shared workflow's `repin` job (no secrets, no credentials, a timeout, the newest bats on PATH,
  `BATS_REPOSITORY` and `REPIN_RECORDS` set) on the base, before the relock decides whether
  anything changed. `repin-paths` is the pins directory: the job refuses a write anywhere else
  and packs that directory as data. The shared workflow commits what the command moved
  (`pins.txt` and the `<name>.xml` files) with the other pins and renders the records, kind
  `android-sdk`, as the pull request body's section `### Moved by the repin command`: the
  package, its old and new revision, the release age and `moved` or `current`. A run where
  nothing moved and no other pin moved opens no pull request.
* **What `relock.sh` does** (shell: the tool is bats, which has no HTTP client, and the tool
  makes no network call; the avenue exhausted is a bats fetch). It builds the tool in a copy of
  the directory (the checkout holds no build output), downloads `repository2-1.xml` and
  `sys-img/android/sys-img2-1.xml` from `dl.google.com/android/repository`, and for each pin
  writes `<archive>.age` (whole days since the `Last-Modified` of a `HEAD`) for the archive the
  pin names and for every archive the feeds list in the `<remotePackage path="P">` blocks of
  that pin's package (P is the `path` of the pin's `<name>.xml`): the newest stable one is among
  them, and the tool reads only the ages it needs. The one text match is an `awk` that lists
  those `<url>` lines; **no XML or YAML is parsed by the script**. The tool reads the feeds
  (below) and moves `pins.txt` and the `<name>.xml` files.
* **Which channel.** The tool follows the stable channel: a revision is stable when its
  `<channelRef ref="X"/>` names the `<channel id="X">stable`. The emulator 37.2.12 is on
  `channel-0` and a newer 37.3.5 is on `channel-2` (dev) in the live feed, so it is not a newer
  pin. The details and the cases are `android-smoke.md` and `tests/android-sdk-pins/repin.sh`.
  Research: `sdkmanager`'s default is the stable channel, and `--channel=N` opts into the
  others; the SDK Manager UI shows stable only unless the user asks for previews.
* **A failure is red.** A feed or an archive that cannot be fetched, an age the tool cannot
  read, a package it cannot examine: the command exits non-zero and the shared workflow
  skips the relock and the publish, so nothing is pushed.
* **The test** is `tests/android-relock/check.sh`, run by `relock-android-test.yml` (not
  `check.yml`: its pull request is open elsewhere): `relock.sh` against fixture feeds
  (`tests/android-sdk-pins/repin/`) served from a directory by `file://` URLs, the archives'
  `Last-Modified` set by `touch`. It shows an emulator older than the stable one moved to the
  feed's revision with the feed's SHA-1 (and the record and the table row name both
  revisions), a run with every pin current changing nothing, a missing age and a missing feed
  failing the run, and that `relock.yml` runs the script. The table is rendered by
  repository-prototype's `repin table`, built from the commit `relock.yml` calls.
* **The audit.** `relock.yml` is no longer the text of repository-prototype's caller template
  (it adds two inputs), so the weekly pin audit lists it by its sha256 in
  `tools/pin-audit/allowlist.txt`, as it lists the other workflows of this repository
  (pwa#190); `relock-android-test.yml` is a workflow of its own and is listed the same way.

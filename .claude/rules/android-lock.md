---
paths:
  - src/lib.bats
  - tests/android-lock/**
  - example/pnpm-lock.yaml
---

# The generated Android project installs from a committed lock (pwa#131, repository-prototype#352 row 8)

`build-android.sh` (`build_android_script_locked` in `src/lib.bats`, written by
`create_android_locked`) installs from a committed lock. The old form,
`build_android_script` and `create_android` (a bare `pnpm install`, no lock),
was published beside it for one version and is removed (bats-lang/pwa#165, no
dependent called it any more; quire moved in quire#735). The old form had no lock: the
plugins' own dependencies (and the `^8.1.0` ranges of Capacitor's core,
Android platform and CLI) resolved to whatever the registry held on the
day, so a commit that built once could build differently later.

* **The lock is the app's, committed beside the project.** The project is
  written afresh by every build (`rm -rf android`, a generated
  `package.json`), so the lock cannot live in it: the app commits
  `pnpm-lock.yaml` and puts it next to `build-android.sh`, as the example
  does (`example/pnpm-lock.yaml`, copied by check.yml). pwa generates no
  lock and adds no input to `create_android_locked`.
* **The refusal comes first (pwa#164).** The check for `pnpm-lock.yaml` is
  before `. ./fetch-pnpm.sh`: it needs nothing from pnpm, so an app without a
  lock is told so before pnpm is downloaded and checksummed. The locked form
  is the only user of `_android_script_head` and `_android_script_pnpm`.
* **The install is frozen.** The script stops with a message when there is
  no `pnpm-lock.yaml`, then runs `pnpm install --frozen-lockfile`: it
  fails when the lock does not match `package.json` (pnpm's
  `ERR_PNPM_OUTDATED_LOCKFILE`) and never rewrites the lock. The lock is
  made in a clean directory with the generated `package.json` and the
  `nodeLinker: hoisted` workspace file, by `corepack pnpm@12.9.1 install
  --lockfile-only`; the line is in the script's own comment.
* **Process, not a capability.** What the app does, the APK's plugins and
  what pwa generates besides the script's install line do not change;
  `tests/android/plugins.py` still checks `package.json` against bridge's
  table. It is the same rule as `e2e-setup`'s `npm ci`.
* **Research.** npm's `npm ci` and pnpm's `--frozen-lockfile` are the
  documented way to install exactly a lock (both fail on a mismatch and
  never write it; pnpm's documented default for `--frozen-lockfile` is
  true in CI only "if a lockfile is present", so with none a CI install
  would resolve afresh, which is why the script requires the file).
  Capacitor's environment-setup docs say nothing of lock files or CI
  installs (read for this), so nothing is taken from them. Cargo's
  `--locked`, Bundler's frozen mode and Gradle's dependency locking are
  the same shape. A lock whose entries are git
  subfolder tarballs (the google-authorize plugin) pins by commit.
* `tests/android-lock/check.sh <build-android.sh>` (a step of check.yml)
  plays it: no lock refused with corepack never called; a lock, then
  `install --frozen-lockfile` once; with the real pnpm, a lock it made
  passes and a `package.json` that gained a dependency fails with the lock
  byte for byte as it was. It replaces `fetch-pnpm.sh` (sourced by
  `build-android.sh`, pwa#158) with a stand-in that records that it ran and
  names the pnpm (the no-lock case fails if it ran),
  whose download `tests/android/pnpm.sh` tests. Every blocking call of the test has a hang guard
  (`timeout`, stdin closed), and the step has `timeout-minutes`: a run once sat
  3 h 53 min because the stand-in corepack ran `exec corepack ...` by name
  and found itself again; the real program is named by absolute path. The `android` job of check.yml installs the
  example's lock for real.

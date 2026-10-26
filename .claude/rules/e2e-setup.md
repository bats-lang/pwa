---
paths:
  - .github/actions/e2e-setup/**
  - tests/e2e-setup/**
---

# The e2e setup action (quire#637)

An app's e2e job installs Node's packages and Playwright's browsers
before `gen-pwa test`, and a dropped connection to the registry there
(quire#635: `ECONNRESET`, 16 minutes in, a merge queue entry lost) ran no
test. `.github/actions/e2e-setup` is a composite action, called by commit
as `android.yml` is (`uses: bats-lang/pwa/.github/actions/e2e-setup@<sha>`,
after the checkout), that does it once for every app:

* `actions/setup-node` with `cache: npm` (the downloads, keyed on the
  lock's hash; `cache-dependency-path` follows `working-directory`);
* `npm ci` (exactly `package-lock.json`: it fails on a lock that does not
  match `package.json` and never rewrites it) with `--fetch-retries=5`
  (npm's default is 2) and npm's default 10 s to 60 s backoff, and the
  whole install again, up to 3 tries with a doubling pause, when it fails
  with a connection's error (`retry.sh`), or an index or archive cut short
  (sdkmanager's `ZipFile unknown archive`, and `parsing problem. XML document
  structures must start and end within the same entity`, both with exit 0 or
  a missing package after); any other failure ends at once;
* the installed Playwright version read from `playwright-core` and
  refused below `playwright-minimum` (pwa#92's reason: quire's fake clock
  needs 1.58), with the message saying why;
* one browsers directory, `$RUNNER_TEMP/ms-playwright`, exported as
  `PLAYWRIGHT_BROWSERS_PATH` (what `gen-pwa test` checks), restored and
  saved by `actions/cache` under the key `playwright-browsers-<os>-<arch>-<Playwright
  version>`, so the key moves when the lock moves Playwright and never
  with the app, and then `playwright install chromium`, retried the same
  way (a hit finds the directory complete and downloads nothing).

It is CI and process, not a change to `gen-pwa test`: that command is
documented to check the browsers and never download them (pwa#82), and
"Changes to pwa" allows only bug fixes and new platforms, so a test
runner that installs packages over the network would be a new feature of
pwa. Playwright's CI documentation says caching the browsers "is not
recommended, since the amount of time it takes to restore the cache is
comparable" and, if done, to key it on the Playwright version; the cache
is here for the registry-free, CDN-free path, not for speed, and
`cache-browsers: false` turns it off. `tests/e2e-setup/check.sh` runs the
scripts against a fake npm and against the real npm and a registry stub
that resets the first N connections (inside npm's retries, past them, for
ever), a lock out of sync, a missing lock, the minimum and the key; the
`check` job runs it, and the example is the action's first user (its
`package-lock.json` is committed for that).

## The stall tools (`stall-tools: "true"`, pwa#178, pwa#163)

An app's stall capture (quire#575) takes native stacks of a frozen renderer
with gdb, elfutils (`eu-stack`), libc6-dbg of exactly the installed libc6 and
rr. The input `stall-tools` (default `"false"`) runs `stall-tools.sh` after
the browsers, on a runner that keeps its passwordless sudo. Every apt call is
bounded twice: apt's own `-o Acquire::http::Timeout`, `Acquire::https::Timeout`
(30 s) and `Acquire::Retries=3`, and `timeout -k 10` around the call
(`E2E_APT_HANG_S`, 600 s: a hang guard for what apt's options do not reach,
never a budget), so a stalled mirror makes an attempt fail and the next of 3
attempts run (a call that never returns would stop the attempts after it).
A diagnostic for a rare freeze never fails the
job: what cannot be installed is a warning and the script exits 0. No
wall-clock budget bounds the step. `tests/e2e-setup/check.sh` plays an
`apt-get` that never returns on its first call, and on every call.

The script is shell because a composite action's steps are shell and the
action's other scripts already are (`retry.sh`, `npm-ci.sh`); `timeout` and
`apt-get` are the tools it drives, and bats has no process to run in a runner
before bats is built.

## The Japanese font (`japanese-font: "true"`, pwa#226, quire#907)

An app whose pages draw Japanese text needs a font with the characters, or
the page shows empty boxes. Quire installed `fonts-noto-cjk` with apt in each
of its 8 e2e groups: a 61.2 MB package from the runner image's mirror, which
some runners reach at 55 kB/s (18 min 32 s in one job, 4 s in a fast one).
Research: Playwright's dependency list for Ubuntu 24.04
(`nativeDeps.js`, `tools`) names `fonts-ipafont-gothic` (3.5 MB) and
`fonts-wqy-zenhei` (7.5 MB) and no Noto CJK, and Puppeteer's troubleshooting
guide installs the same two; `e2e-setup` runs `playwright install chromium`
without `--with-deps`, so it had none. Measured on quire main (Playwright
1.61.0, chromium headless shell 1228, `vertical.spec.js` and
`two-books.spec.js`, 23 tests): IPAGothic alone 23 passed, WenQuanYi alone 23
passed, no CJK font 1 failed (the spec's own precondition, by name), 1 skipped.

So the input installs IPAGothic: its deb (`fonts-ipafont-gothic`
00303-21ubuntu1, 3 513 360 bytes, SHA-256 of Ubuntu's `Packages` index) is
fetched by `curl` (archive.ubuntu.com, then Launchpad), checked against that
hash, extracted with `dpkg-deb -x`, and its two fonts kept in
`$RUNNER_TEMP/japanese-font` by `actions/cache` under
`japanese-font-ipafont-gothic-<version>-<12 hex of the deb's hash>`. The
key is only a locator: a restored directory is used only when both fonts
match their pinned SHA-256 (else the deb is fetched again), and a download or
hash that fails fails the step. The fonts go to
`~/.local/share/fonts/pwa-e2e-japanese` with `fc-cache`: no apt, no sudo.
Shell for the reason the other scripts are. `tests/e2e-setup/check.sh` plays
a miss, a hit, a damaged cache, a first URL that fails, a deb with another
hash and no working URL.


### Avenues searched before writing `japanese-font.sh` and its checks (pwa#242)

Non-bats code of ours needs the avenue it exhausted. Searched, 2026-10-26:

* **An apt package cache action** (awalsh128/cache-apt-pkgs-action, its README: "a composition of actions/cache and the apt utility"): on a miss it runs apt against the same throttled mirror, has no second URL and no SHA-256 of our own, is "in maintenance mode" for v1, and its README warns of packages whose install scripts or dpkg state do not restore. It would still be an action of a third party to pin, and the miss (the 18 minute case) is the case that matters. `actions/cache` of `/var/cache/apt/archives` needs root and apt on the miss for the same reason.
* **Playwright's own install of these fonts** (`playwright install --with-deps`, `nativeDeps.js`): it runs `apt-get install` for the whole Ubuntu 24.04 list (dozens of packages, not one 3.5 MB deb) through sudo and the same mirror, and has no cache or hash of ours; the browsers it downloads from its own CDN bundle no CJK font. `e2e-setup` runs it without `--with-deps` on purpose (pwa#82's rule that nothing installs system packages).
* **A bats test instead of `check.sh`**: the script runs in a runner step before bats is built (a composite action's steps are shell), so what it does cannot be bats; a bats test of it would spawn the same shell script with the same stand-ins and add a build of bats to a job that has none. `check.sh` is where `retry.sh`, `npm-ci.sh` and `stall-tools.sh` are already checked, run by the `check` job.
* **The font in the repository** (3.5 MB of binary in git): rejected, a font file of third-party licence in the tree and in every clone, against a pinned hash of Ubuntu's own file.

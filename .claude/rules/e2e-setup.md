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
  with a connection's error (`retry.sh`); any other failure ends at once;
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
attempts run (`apt-get update` once never returned for 56 minutes and the
attempts after it never ran). A diagnostic for a rare freeze never fails the
job: what cannot be installed is a warning and the script exits 0. No
wall-clock budget bounds the step. `tests/e2e-setup/check.sh` plays an
`apt-get` that never returns on its first call, and on every call.

The script is shell because a composite action's steps are shell and the
action's other scripts already are (`retry.sh`, `npm-ci.sh`); `timeout` and
`apt-get` are the tools it drives, and bats has no process to run in a runner
before bats is built.

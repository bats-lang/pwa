---
paths:
  - src/test_run.bats
  - tests/test-command/**
---

# gen-pwa test (pwa#82)

`test_wanted` and `test_run` (`src/test_run.bats`) are the app
generator's `test` subcommand: an app's gen-pwa calls them when its
first argument is `test`, as the example's `build-pwa` does. They run the
app's Playwright suite against its built `dist/pwa`; they are tooling
for the app's tests, not part of anything pwa generates or the app runs,
so a change to them is a process change (see "Adversarial review before merge" in CLAUDE.md). A run
takes a slot of the machine's lock (flock, file's `fd_lock`, on one of
`PWA_TEST_SLOTS` files in `PWA_TEST_LOCK_DIR`); a run that cannot take one
(directory, file or lock unavailable) is refused, said, exit 1, and runs
nothing (bats-lang/pwa#155, the `_lock_refused` predicate), as `flock(1)`
does (it exits 66 on an open failure and 1 on a busy lock under `-n`); the
research is on that issue. It checks that the browsers'
location holds the headless Chromium the project's Playwright expects
(never downloading), runs the tests tagged `@serial` alone on one worker
and then the others (on half the cores divided by the slots), each
through a keeper (`node -e`: Bats has no sockets; the browser check
reads Playwright's `browsers.json` with `node -e` too, and these two are
its only JavaScript) that serves `dist/pwa` at a port the kernel picks
(`PWA_TEST_BASE_URL`) and stops Playwright's process group when gen-pwa
ends, however it ends. It also refuses a Playwright older than 1.58 (pwa#92: `version_read_of`,
`version_support`, a total read of the version into a `version_read` and a
`support`, not a comparison of strings; the floor is a constant, the app
raises it by its own `package.json`, and e2e-setup's `playwright-minimum`
is the same check in CI). `bats test` tests the read
(`$UNITTEST` block of `src/test_run.bats`); `tests/test-command/check.sh`
checks the command with a stand-in Playwright (`PWA_TEST_PLAYWRIGHT`) and
stand-in versions. The design and what was
searched are on bats-lang/pwa#82.

## The page watch (pwa#132, pwa#230)

Every run also supplies a preload to Playwright's processes, so a hung page
leaves evidence with no import in a spec and no change of the app's config.
`_watch_source` (`src/test_run.bats`) is its text, passed to the keeper in
`PWA_TEST_WATCH_SOURCE`; the keeper writes it to a temporary `watch.cjs`, adds
`--require="<file>"` to the child's `NODE_OPTIONS` (the caller's kept before it)
and removes the file when it exits. The preload wraps `launch` of the project's
own `playwright-core` (resolved from the working directory; on any surprise the
launch is left as it was), so each browser a test gets is watched: pages are
armed from its creation (the browser's `newContext` is wrapped to listen for the context's `page` event, and a scan every 0.5 s is the fallback) with a DevTools session (debugger on, breakpoints off), asked to evaluate
`1` every 2 s, and captured when one does not answer in 5 s or when the running
test (`test.info()`) is within 15 s (a third of a shorter timeout) of its
timeout. A capture is the pause frames, else a 2 s CPU profile, the page's last
100 console messages, errors and failed requests with the requests in flight,
and the runner's load and pressure, in `<--evidence dir>/<project>-<test>-<n>.json`
(default `pwa-evidence`, `PWA_TEST_EVIDENCE_DIR`; Playwright clears `outputDir`,
which is why it is not under it), with one line on stderr naming the file. A
part that cannot be taken is `not available: <why>`; nothing fails a test.

Why a preload: the measured alternatives are on pwa#132 (comment 6424242835): a
reporter or `globalSetup` runs in the runner process and has no page; an auto
fixture needs the spec to import `test` from the file; an npm package is code
of the app's own. The text has no double quote and no backslash because it is
written as Bats strings; it is JavaScript because it runs in the workers with
the page's DevTools session (the keeper and the browser check are the others).
`tests/test-command/watch.test.mjs` (`node --test`, run by `check.sh` on the
preload the stand-in run wrote) plays a stand-in `playwright-core` through the
frozen page, the profile, the timeout and each part failing. Native stacks, the
flight recorder, the reporter and the prerequisites check are pwa#231 to #233.
Do not make a directory under `/proc` in a test: node's recursive `mkdir` never
returns there.

Non-bats code here, and the avenue exhausted (pwa#230, keyword: non-bats): the
preload and `watch.test.mjs` are JavaScript because the behaviour is that of a
node process (a `--require` hook, the wrapped `launch` of `playwright-core`, the
page's DevTools events); searched: the `$UNITTEST` block of `src/test_run.bats`
and `bats test` (pure Bats functions, no JavaScript engine and no way to load
`playwright-core`), `bats_modules/process` and `file` (they can spawn and read a
process, but not play a page's session), `tests/dynamic` (shell too); node and
`node:test` are what Playwright itself needs, so no new dependency. The
`check.sh` lines extend the harness that already checks every option of
`gen-pwa test` through the built binary and a stand-in Playwright (a `#!/bin/sh`
program, because the stand-in must be an executable and `check.sh` writes it
next to its assertions); a Bats test could spawn the binary through `process`,
but it would need that same stand-in executable, so it moves the shell and does
not remove it.

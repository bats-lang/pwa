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
`PWA_TEST_SLOTS` files in `PWA_TEST_LOCK_DIR`), checks that the browsers'
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

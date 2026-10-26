---
paths:
  - src/static_pages.bats
  - tests/static-pages/**
---

# gen-pwa pages (pwa#243, piece 1 of pwa#133)

Keyword: static-pages. `pages_wanted` and `pages_run` (`src/static_pages.bats`) are the
app generator's `pages` subcommand, called from its main as `test_wanted` is:
`gen-pwa pages SOURCE NAME` copies the tree at SOURCE, files byte for byte (`fd_copy`, with
the source's permission bits), to `dist/pwa/NAME`. It replaces the shell step
`cp -R homepage dist/pwa/homepage` that an app wrote after `gen-pwa`. The app names the
directory and the name; pwa holds no policy about which pages. It is build tooling for the
app's CI (process, the class of `gen-pwa test`): it changes nothing pwa generates and nothing
the app runs, and it takes no capability.

Outcomes, each said on stderr with the path and the system's reason, exit 1 (the exit is 0
only for `PagesCopied`); the outcome type has a constructor for each, no data, matched with
`case+`:

* `PagesUsage`: not exactly SOURCE and NAME, or the arguments over 4096 bytes.
* `PagesNameRefused`: NAME empty, `.`, `..`, or holding a slash, so it cannot leave `dist/pwa`.
* `PagesSourceRefused`: SOURCE is not a readable directory. Checked before anything is made.
* `PagesDestinationExists`: `mkdir dist/pwa/NAME` answered EEXIST (the system's own answer, so
  there is no check-then-make gap), nothing was touched.
* `PagesReadFailed`, `PagesWriteFailed`: a directory, file, open, copy or close that failed.
* `PagesPathTooLong`: a path of 524288 bytes or more.
* `PagesTooDeep`: more than 64 levels (`PAGES_DEPTH`), so a symbolic link that loops ends. The
  recursion's termination is the metric of the depth, a type, not a runtime guard.

A symbolic link is followed (a link to a directory is copied as a directory). The file package
has no lstat; the avenue for non-bats code in the test is `tests/static-pages/check.sh`
(driving the built binary and comparing trees with `diff -r`, a third-party tool used as it is,
as `tests/test-command/check.sh` does).

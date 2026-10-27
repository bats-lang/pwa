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
* `PagesTooDeep`: more than 64 levels (`PAGES_DEPTH`), so a symbolic link that loops ends. The
  recursion's termination is the metric of the depth, a type, not a runtime guard.

A symbolic link is followed (a link to a directory is copied as a directory).

Types, not checks: the arguments are read from a 4096-byte buffer by indices proved `<= k <= 4096`
(`_arg_end`, `_after`, `_name_ok`; no `g1ofg0`, no clamp), every path is a `builder(n)` whose put
is typed `n < 524288`, and the copy carries `sk + 1024 * d + 1024 < 524288` (and the same for the
destination) with the depth `d` left, so a path of a copy (at most 4096 bytes of argument plus 64
levels of names under 1024 bytes) always fits and the zero after it exists. No byte is dropped
and no length is tested at run time.

Tests: `tests/static-pages` is a bats project (`bats test`, run by check.yml after the example is
built; `src/lib.bats`). It runs the built binary in a case directory `build/pages-tests/NAME` with
`env -C`, reads its exit status and its whole standard error, and checks the words (the path and
the system's reason) of every outcome: a copy, a destination that exists, a missing source and a
file as source, each bad name, the three usage errors, a read-only `dist/pwa` and a missing one, a
dangling link, a looping link, an unreadable file and a tree of 66 levels. The modes are read with
the file package. The trees are compared by `diff -r`, a third-party tool used as it is (the file
package has no lstat and no symbolic link, nor a tree comparison; `mkdir -p`, `rm -rf` and `ln -s`
make the cases for the same reason), with a control that makes `diff -r` fail on a changed file, a
missing file and a missing directory. The two cases that need an unprivileged user (a read-only
dist/pwa, a file with mode 0) pass without their words as root, who can write and read; CI runs as
the runner user.

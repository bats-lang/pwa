---
paths:
  - src/public_values.bats
  - tests/values/**
---

# gen-pwa values (pwa#244, the second part of pwa#133)

Keyword: public-values. `values_wanted` and `values_run` (`src/public_values.bats`) are the app
generator's `values` subcommand, called from its main as `pages_wanted` is (after pwa#243, which
merged first): `gen-pwa values ENVFILE OUTFILE NAME:KEY:FORM...` writes `dist/pwa/OUTFILE`, a JSON
object of the app's public values read from a committed env file. It replaces the shell script
that an app ran after `gen-pwa` (quire's `scripts/sync-clients.sh`). The app names the env file,
the output file and, for each value, its env name, its JSON key and its form; pwa holds no
policy about which values or what a good one looks like. It is build tooling for the app's CI
(process, the class of `gen-pwa test`): nothing pwa generates and nothing the app runs changes,
and it takes no capability.

The file is `{"KEY": "value", ...}` and a newline, keys in the order of the arguments: byte for
byte what the quire script writes (`tests/values/check.sh` compares them, with the script and its
env file copied unchanged from quire at 619e898).

**The env file.** Plain `NAME=value` lines, no quotes: a line that does not start with `NAME=` is
not a value (comments, blank lines). A value is printable ASCII without the double quote and the
backslash, so it needs no JSON escape (a quote or backslash is `ValuesValueMalformed`). The file is
read whole, under 524288 bytes (the builder's cap): `ValuesEnvTooLarge` otherwise.

**A form** is a sequence of items, each an atom and an optional count. An atom is a byte (a
backslash makes the next one literal) or a class in square brackets (bytes and ranges `a-z`, a
backslash escapes). A count is `+`, `{n}` or `{m,n}`; none means exactly one. The match is over the
whole value, with backtracking (`_form_from`, `_form_counts`; the termination metric is the
position in the form and then the count, a type, not a guard). The question mark, the star, groups
and alternatives are refused as a form (`ValuesSpecRefused`): a form is the small language the two
forms of quire need (`[0-9]+-[0-9a-z]+\.apps\.googleusercontent\.com`, `[a-z0-9]{8,64}`) and no
more. Counts have at most eight digits.

Outcomes, each said on stderr with the name and the reason, exit 1 (0 only for `ValuesWritten`);
the outcome type has a constructor for each, no data, matched with `case+`. Everything is checked
before the output file is opened, so a refusal writes nothing and leaves an existing file as it was:

* `ValuesUsage`: fewer than ENVFILE, OUTFILE and one spec. `ValuesArgumentsTooLong`: arguments or a
  path of 524288 bytes or more.
* `ValuesOutputNameRefused`: OUTFILE empty, `.`, `..` or holding a slash (it cannot leave `dist/pwa`).
* `ValuesSpecRefused`: a spec that is not NAME:KEY:FORM, an empty or bad NAME (letters, digits,
  underscore) or KEY (the same and dashes), an empty form or one that is not a form.
* `ValuesEnvUnreadable` (the path and the system's reason), `ValuesEnvTooLarge`.
* `ValuesValueMissing`, `ValuesValueRepeated` (more than one `NAME=` line), `ValuesValueMalformed`
  (characters, or not of its form). The first spec that fails ends the check.
* `ValuesOutputTooLarge`: the JSON would be 524288 bytes or more (nothing was dropped silently:
  the builder drops only at the cap, and a length at the cap is refused).
* `ValuesWriteFailed`: the open, the write or the close failed, with the path and the reason. The
  file is made or emptied with mode 0644, as the script's redirection does.

Two specs may name the same key (the app's mistake, a JSON object with a repeated key); pwa checks
no policy of the app's. `ValuesChecked` is the inside of a run, never an end.

The tests (`tests/values/check.sh`, run by `check.yml`) drive the built binary: the byte-for-byte
file, the forms (backtracking, counts, classes, escapes), each refusal above, the large cases and
each way a write fails. The cases that need a user who cannot write (a read-only `dist/pwa`, an
env file without permission) are skipped for root, as in `tests/static-pages/check.sh`. The
avenue for non-bats code is that driver (a third-party shell around the built binary and quire's
own script as the reference); the code under test is bats.

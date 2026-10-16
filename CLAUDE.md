# pwa

pwa writes the shell around a Bats WASM app: the PWA's `index.html`,
`manifest.json`, `bridge.js` and service worker, and the Capacitor
project of its Android app.

## pwa emits no JS logic

JS lives only in bridge, as thin atoms (each with its `*_available`,
its answers decoded into datatypes), and the app's logic lives in the
app, in Bats, on those atoms (bats-lang/pwa#49).

* The page's one script is bridge's (`bridge.js`); `index.html` holds no
  inline script, and no element, class or attribute of pwa's own
  (`pwa-*`, `data-pwa-*`) that a script would act on.
* The service worker is bridge's (`produce_service_worker`), share
  target included: pwa adds no handler to it.
* The Android activity (`MainActivity.java`) runs no JS of its own: it
  calls bridge's entry points, `globalThis.batsNative.deliverFile(url,
  name)` for a file it hands over and `globalThis.batsNative.key(name)`
  for a volume key, one call each, and reads their answer. It calls one
  only once `batsNative` exists (a share can start the app before its
  page has loaded bridge.js); until then the answer is false.
* The Android smoke test runs on AOSP's emulator image, without Google
  Play services: on a fresh boot they restart their process at no set
  time, and Android kills every app holding a connection to one of
  their providers, as Android System WebView does to their FontsProvider
  (quire#220). The system image is cached between runs.

## gen-pwa test (pwa#82)

`test_wanted` and `test_run` (`src/test_run.bats`) are the app
generator's `test` subcommand: an app's gen-pwa calls them when its
first argument is `test`, as the example's `build-pwa` does. They run the
app's Playwright suite against its built `dist/pwa`; they are tooling
for the app's tests, not part of anything pwa generates or the app runs,
so a change to them is a process change (see the review below). A run
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

## The e2e setup action (quire#637)

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

## The Play release workflow (pwa#90, quire#623)

`android.yml` ends at the artifact `release-aab`; what came after was
copied by every app (quire's `play-internal` job). `.github/workflows/play-release.yml`
is a reusable workflow, called by commit as `android.yml` is, that
downloads that artifact, signs in to Google by Workload Identity
Federation (`google-github-actions/auth`; no key is stored) and runs
`scripts/play-release.sh`, which releases the AAB to a Play testing track
(internal by default, `production` refused) through the Developer API's
edits: insert, upload the bundle, set the track to a completed release
with the notes (500 characters), commit with `ERROR_IF_IN_REVIEW`, and
delete an edit that does not commit. `tests/play-release/run.sh` (a step
of the `check` job) checks it against a stub of Play, and that every
action the workflow uses is pinned by a commit with its version.

* **Process, not a capability.** Nothing pwa generates changes, and
  nothing the app runs: it is a release step of an app's CI, as
  `android.yml` and the e2e-setup action are, and it holds no secret.
* **The script is taken from the commit the caller names (`pwa-ref`).** A
  reusable workflow cannot read the commit it was called at (`github.sha`
  and `github.workflow_sha` are the caller's), so it checks out
  `bats-lang/pwa` at the `pwa-ref` input, only `scripts/`. A composite action
  would know its own files (`github.action_path`, as e2e-setup does) but
  could not take the `id-token` permission or the job's `concurrency`; the
  caller passes its pin twice instead.
* **Who may release is Google's side, not this workflow's.** The provider's
  attribute condition (the calling repository, the ref, the event) admits
  the runs that get the service account's token; the workflow checks
  nothing of the kind, and the README says what the app's owner sets up.
  The token's `repository` claim is the caller's in a reusable workflow
  (`job_workflow_ref` names this file), so a condition on the calling
  repository holds.
* **Inputs reach the shell as environment variables**, never spliced into a
  script, so a commit message cannot inject into the step.
* Pins (by commit, verified with `git ls-remote` on the tag):
  `actions/checkout` v4, `actions/download-artifact` v4,
  `google-github-actions/auth` v3.0.0.
* The first run is an app's: the workflow needs Google, so only an app's
  push to main exercises it end to end (its `dry-run` input validates the edit
  and releases nothing).

## The signing key's fingerprints (pwa#96, quire#623)

`android.yml` printed nothing of the key it signs with, and an app's own
workflow (quire's `sync-identity.yml`) decoded the keystore again to print
the upload key's SHA-1 and SHA-256 and to refuse a registered Play app
signing SHA-1 that is the upload key's (quire#200: the Android OAuth
client was registered with the upload key's certificate, which an app
installed from Play, signed by Play's own key, does not carry).
`scripts/key-fingerprints.sh` does both for every app; android.yml's steps
call it when `pwa-ref` is given (the script is taken from that commit, as
play-release.yml's is) and `play-signing-sha1` adds the refusal.

* **Process, not a capability.** It reads the keystore android.yml already
  decodes and signs with; nothing pwa generates changes. Without the new
  inputs the workflow does what it did.
* **No secret in output.** The password reaches keytool as
  `-storepass:env` (on no command line; the decode step's own keytool call
  uses it too); keytool's listing is never
  printed, only the two fingerprints, which every signed APK carries.
* **`pwa-ref` is optional so existing callers are unchanged.** Taking the
  script from the default branch instead would be an unpinned input.
  `pwa-ref` must be 40 lower case hex digits (checked before the checkout).
  A `play-signing-sha1` with no `pwa-ref` or no signing key fails rather
  than skip a check that was asked for.
* `tests/key-fingerprints/run.sh` (a step of `check`) makes keystores with
  keytool, compares the printed digests with openssl's of the exported
  certificate, and checks the refusals and acceptances. The workflow's
  steps need an app's secrets and run in an app's job.

## Changes to pwa

Further changes to pwa are disallowed: the only modifications allowed
are bug fixes (current functionality that misbehaves) or adding new
platforms (iOS, Electron, …). A feature the app needs from the platform
is a bridge atom and the app's own code, never pwa's.

## CI is pinned

Every input to CI is pinned in the source (bats-lang/repository-prototype#269),
so a commit that passes keeps passing:

* `bats.lock` is committed: CI never runs `bats lock` for the package, so
  `bats check` and `bats build` fetch exactly the locked versions, and fail
  when the lock is missing or does not match `bats.toml`. A library's lock
  pins only its own CI and tests; its dependents still resolve their own.
* The compiler is the commit in `.github/bats-version`, read by every
  workflow that builds bats (and by the publish workflow).
* The package repository is fetched at the commit in
  `.github/repository-version`, so what the test packages under `tests/`
  lock (`bats lock --dev`) is pinned too.
* `publish.yml` and `relock-pins.yml` in bats-lang/repository-prototype are
  called by commit, never `@main`.

Pins move only through a reviewed pull request that runs the same CI. The
daily `relock.yml` (the shared `relock-pins.yml`) relocks against the
newest, moves the compiler and repository pins, pushes `relock/<date>`,
opens a pull request listing the old and new versions and dispatches
`check.yml` on it, so a breaking publish shows as a red relock pull
request and main stays green. GITHUB_TOKEN cannot change workflow files,
so without a `RELOCK_TOKEN` secret that pull request lists a workflow pin
that would move instead of moving it: move it in a pull request of its
own. A pull request that needs newer packages runs `bats lock
--repository <dir>` and commits `bats.lock` (and
`.github/repository-version`) with the change.

## Adversarial review before merge

No pull request merges before an adversarial review: a comment on the
pull request (its form is below), written by someone other than its
author (another agent or a person). The review first confirms the
pull request's kind from its diff, whatever the author called it.
A review knows three kinds: the two changes to pwa itself that "Changes
to pwa" allows (a bug fix, a new platform), and a change to process,
documentation or CI, which changes nothing pwa does:

* **A bug fix** (current functionality that misbehaves, against what it
  is documented to do): the review confirms it really is a deviation
  from the spec, that the fix is minimal, and that no capability slipped
  in: a "fix" that adds native behaviour, a plugin, a JS handler or
  anything else pwa did not do is reviewed as a capability, and so is
  refused unless it is a new platform.
* **A new platform** (iOS, Electron, …), the one new capability pwa
  takes: the review answers, with evidence (code, measurements, the
  platform's documentation):
  1. Is there no way to do this with what exists (bridge's atoms and the
     app's own Bats), at reasonable performance?
  2. Is this the minimal wrapper? Does each native piece map 1:1 to the
     platform's API? Why can it not be broken into smaller pieces, each
     a bridge atom? (Always asked; in detail when it is not 1:1.)
  3. Does the native side decide anything? It may only hand an event or
     a value to one of bridge's entry points (`batsNative`) and read its
     answer, as `MainActivity.java` does.

  The review analyzes the plausible alternatives and says why each
  would not work: a bridge atom on the web API the platform's web view
  already has, an existing entry point, the app doing it in Bats.

  Any other capability (a Capacitor plugin, native connectivity, native
  code pwa generates for a feature) gets `Verdict: changes needed`: a
  feature the app needs from the platform is a bridge atom and the
  app's own code, never pwa's.
* **Process, documentation or CI** changes: the review confirms they add
  no capability. Test tooling (gen-pwa test, which runs an app's suite)
  is process: the review confirms it changes nothing pwa generates and
  nothing the app runs.

A DOM write is never pwa's: it is an opcode of bridge's diff stream,
issued by the app. App policy (which attributes, roles, defaults, when)
never lives in pwa's generated native code or page: it is the app's, in
Bats (bats-lang/pwa#49). A pull request that puts either in pwa gets
`Verdict: changes needed`.

### Who reviews, and where

Only a comment by a trusted author counts: its `author_association` is
OWNER, MEMBER or COLLABORATOR. These repositories are public, so anyone
else's comment, approving or not, is ignored; the gate's log names each
review attempt's author and association, and the status says "No review
by a trusted author" with the associations it saw. The reviewer is
another agent or person than the one that wrote the change: all agents
here post from one account, so the review is done by a separate
reviewer agent, named on its `Reviewer:` line.

A review that approves is a comment in the pull request's conversation,
not a formal pull request review and not a line comment. A formal review
by a trusted author can only block:

* its text is read like a comment's (as rendered), ordered with the
  comments by when it was submitted, so a formal review that is the
  newest review attempt makes the gate pending, whatever it says (the
  agents post from the pull request author's account, so their formal
  reviews can only be "Comment" reviews);
* one that requests changes (GitHub's "Request changes") stands, as
  GitHub's own rule does, until it is dismissed, whatever comments
  follow.

### The review comment

The gate reads each comment (and each formal review's text) twice: as written, and as GitHub renders it
(`body_text`, GitHub's own plain text of the comment), so what it judges
is what a reader sees. A comment is a review attempt when one of the
first three non-blank lines of either says "adversarial review", read
loosely: NFKC, no zero-width characters, BOM, combining marks or CR,
lower case, entities, escapes, link targets and marks dropped, digits
read as the letters they look like, any non-ASCII letter standing for
any letter, and up to two letters wrong. The newest attempt decides,
alone; an older one never counts again. It approves only when it is
perfectly formed:

* written, its first line is exactly `## Adversarial review`, and shown,
  its first line is `Adversarial review`;
* written and shown, it has exactly one line with `Verdict:` in it (or
  starting with the word), and that line is exactly `Verdict: approved`
  (or `Verdict: changes needed`): no bold, no indent, no trailing space
  or period, no other words;
* written, it has exactly one line with `Reviewed:` in it (or starting
  with the word), and that line is exactly `Reviewed: <SHA>`, the full
  40-character lowercase SHA of the pull request's head commit it
  reviewed; shown, that line is the same, with the SHA as GitHub
  shortens it (7 digits) or in full;
* written, its letters are ASCII, and it has no invisible (format)
  characters, no combining marks, no code fence (three backticks or
  three tildes, anywhere), no HTML comment, no HTML tag (`<` followed by
  a letter or `/`) and no link or footnote definition (a line starting
  `[…]:`). Reviews use inline code and plain text only.

A verdict is never edited: an edited review counts as no approval, and a
new verdict is a new comment. Anything short of the form above is
pending, whatever it says; the status's description says what is wrong.
Other comments should not say "adversarial review" in their first three
lines: such a comment is an attempt, and as the newest it makes the gate
pending.

### The gate

`.github/workflows/review-gate.yml` sets the commit status
`adversarial-review` on the pull request's head commit (read from the
pull request, exactly 40 lowercase hex digits, three tries): success
only for a perfectly formed, unedited approval of the current head in
the newest attempt by a trusted author, with no standing request for
changes. Anything else is pending, and so is any failure (an API error,
a parse error, any unexpected exit), so an earlier success never
outlives a failed run. A push after an approval turns it back to
pending, until a new review names the new head.

It runs on every pull request event (`pull_request_target`), every
comment created, edited or deleted (`issue_comment`), every formal
review submitted, edited or dismissed (through
`.github/workflows/review-gate-relay.yml`, which has no permissions and
does nothing: `pull_request_review` would run the pull request's own
copy of a workflow, so the relay's completion runs the gate through
`workflow_run`), and over every open pull request about every 15
minutes, best effort (`schedule`). All of them run the gate as the
default branch has it, never as the pull request has it; it checks out nothing and runs no code
of the pull request, which is what makes that safe. The relay is only a
fast path; correctness rests on the schedule. It uses no action, only
the runner's `gh` and `python3`.

Known limits:

* Any workflow or token with `statuses: write` can post an
  `adversarial-review` status, so a pull request that adds or changes a
  file in `.github/workflows` could forge one. Such a pull request is a
  process change, and its review must check exactly this: that no
  workflow it adds or changes can post the status or widen its
  permissions to do so, and that the gate and its relay stay as they
  are.
* A commit status belongs to a commit, not to a pull request: two pull
  requests with the same head commit share one `adversarial-review`
  status, set by whichever ran last.
* A pull request can change or delete its own copy of the relay, and a
  fork's runs can wait for "Approve and run": a formal review's effect
  then waits for the next comment, push or scheduled run.
* The schedule is about every 15 minutes, best effort: GitHub delays
  scheduled runs under load and sometimes drops them, and turns a public
  repository's schedules off after 60 days without activity; they stay
  off until someone enables the workflow again (Actions → review-gate →
  Enable workflow). A scheduled run and an event's run are not in one
  concurrency group, so a scheduled run that read the comments just
  before a new review can post after that review's own run, until the
  next run.
* A review attempt is seen only by its first three non-blank lines, and
  only its one Verdict line is judged: a header further down, or prose
  that contradicts the exact approved line, is not caught. Each needs a
  careless or bad-faith review that still writes the exact approved
  line.
* If every lookup of the head fails on a comment event, nothing can be
  marked; the next scheduled run decides.
* The gate checks the comment's form and its author's association, not
  which agent or person wrote it: under one account, the authoring
  agent could post a perfectly formed approval itself; and a header misspelt by more than two
  letters is not seen as an attempt.
* Deleting the newest review makes the one before it the newest again.
  So does editing a formal review: the API gives a formal review no edit
  time, so an edit is not detected, and a trusted reviewer who edits a
  blocking formal review so that it is no longer a review attempt makes
  the older approval the newest again.
* Dismissing a "Request changes" review ends the standing request, but
  not the review attempt its text is: while it is the newest attempt,
  the gate stays pending, and a new review comment is still needed.
* Line comments on the diff are not read: a review posted only as a
  line comment does not block.
* An organization member whose membership is private may show as
  CONTRIBUTOR to the workflow's token, so their reviews do not count:
  the gate's log shows the association it saw. Make the membership
  public, or add them as a collaborator.

`adversarial-review` must be made a required status check of `main` by
a repository admin (Settings → Branches → the rule for `main` →
Require status checks to pass before merging → add
`adversarial-review`); until then the gate only reports. The pull
request template (`.github/pull_request_template.md`) asks the author
the same questions; the reviewer checks the answers, not just their
presence.

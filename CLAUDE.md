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
Under "Changes to pwa", only two kinds of change to pwa itself are
allowed, so a review knows only these (and changes to process,
documentation or CI):

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
  no capability.

A DOM write is never pwa's: it is an opcode of bridge's diff stream,
issued by the app. App policy (which attributes, roles, defaults, when)
never lives in pwa's generated native code or page: it is the app's, in
Bats (bats-lang/pwa#49). A pull request that puts either in pwa gets
`Verdict: changes needed`.

### Who reviews, and where

Only a comment by a trusted author counts: its `author_association` is
OWNER, MEMBER or COLLABORATOR. These repositories are public, so anyone
else's comment, approving or not, is ignored. The reviewer is never the
pull request's author; agents here post under one account, so the
review names its reviewer.

A review is a comment in the pull request's conversation, not a formal
pull request review and not a line comment. A formal review that
requests changes (GitHub's "Request changes") still blocks: while the
newest one by a trusted author is newer than the deciding comment, the
gate is pending. Dismiss it, or post a new review comment after it.

### The review comment

A comment is a review attempt when, after Unicode NFKC normalization,
with zero-width characters, a BOM and carriage returns removed, and
lower-cased, one of its first three non-blank lines contains
"adversarial review" (a non-ASCII letter there stands for any letter).
The newest attempt decides, alone; an older one never counts again. It
approves only when it is perfectly formed:

* its first line is exactly `## Adversarial review`;
* it has exactly one line with `Verdict:` in it, and that line is
  exactly `Verdict: approved` (or `Verdict: changes needed`): no bold,
  no indent, no trailing space or period, no other words;
* it has exactly one line with `Reviewed:` in it, and that line is
  exactly `Reviewed: <SHA>`, the full 40-character lowercase SHA of the
  pull request's head commit it reviewed;
* its letters are ASCII, and it has no invisible (format) characters;
* it has no code fence (three backticks or three tildes, anywhere), no
  HTML comment and no HTML tag (`<` followed by a letter or `/`).
  Reviews use inline code and plain text only.

A verdict is never edited: an edited review counts as no approval, and a
new verdict is a new comment. Anything short of the form above is
pending, whatever it says; the status's description says what is wrong.

### The gate

`.github/workflows/review-gate.yml` sets the commit status
`adversarial-review` on the pull request's head commit: success only
for a perfectly formed, unedited approval of the current head in the
newest attempt by a trusted author, with no newer request for changes.
Anything else is pending, and so is any failure (an API error, a parse
error, any unexpected exit), so an earlier success never outlives a
failed run. A push after an approval turns it back to pending, until a
new review names the new head.

It runs on every pull request event (`pull_request_target`), every
comment created, edited or deleted (`issue_comment`), and every formal
review submitted, edited or dismissed: `pull_request_review` would run
the pull request's own copy of a workflow, so
`.github/workflows/review-gate-relay.yml`, with no permissions, does
nothing but take that event, and its completion runs the gate
(`workflow_run`). All three run the gate as the default branch has it,
never as the pull request has it; it checks out nothing and runs no code
of the pull request, which is what makes that safe. It uses no action,
only the runner's `gh` and `python3`.

Known limits:

* Any workflow or token with `statuses: write` can post an
  `adversarial-review` status, so a pull request that adds or changes a
  file in `.github/workflows` could forge one. Such a pull request is a
  process change, and its review must check exactly this: that no
  workflow it adds or changes can post the status or widen its
  permissions to do so.
* The gate checks the comment's form and its author's association, not
  which agent or person wrote it.
* Deleting the newest review makes the one before it the newest again.
* An organization member whose membership is private may show as
  CONTRIBUTOR to the workflow's token, so their reviews do not count:
  make the membership public, or add them as a collaborator.

`adversarial-review` must be made a required status check of `main` by
a repository admin (Settings → Branches → the rule for `main` →
Require status checks to pass before merging → add
`adversarial-review`); until then the gate only reports. The pull
request template (`.github/pull_request_template.md`) asks the author
the same questions; the reviewer checks the answers, not just their
presence.

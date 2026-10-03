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

### The review comment

The newest comment whose first line is `## Adversarial review` decides,
alone; an older one never counts again. Outside fenced code blocks, it
holds exactly one line that starts (past any markdown marks) with the
word Verdict, and exactly one that starts with Reviewed:

* `Verdict: approved` or `Verdict: changes needed`, exactly: no bold, no
  trailing period, no other words;
* `Reviewed: <SHA>`, the full 40-character lowercase SHA of the pull
  request's head commit it reviewed.

A verdict is never edited: an edited review counts as no approval, and a
new verdict is a new comment.

### The gate

`.github/workflows/review-gate.yml` sets the commit status
`adversarial-review` on the pull request's head commit, on every pull
request event and every comment created, edited or deleted. It is
success only when the newest review is unedited, its one verdict line is
`Verdict: approved` and its one Reviewed line names the current head;
anything else is pending. A push after an approval turns it back to
pending, until a new review names the new head.

It runs on `pull_request_target`, so the gate that runs is the base
branch's file, not the pull request's; it checks out nothing and runs no
code of the pull request, which is what makes that safe.

Known limits:

* Any workflow or token with `statuses: write` can post an
  `adversarial-review` status, so a pull request that adds or changes a
  file in `.github/workflows` could forge one. Such a pull request is a
  process change, and its review must check exactly this: that no
  workflow it adds or changes can post the status or widen its
  permissions to do so.
* The gate checks the comment's form, not who wrote it: agents here post
  under one account, so the review names its reviewer, and the reviewer
  is never the author.
* Deleting the newest review makes the one before it the newest again.

`adversarial-review` must be made a required status check of `main` by
a repository admin (Settings → Branches → the rule for `main` →
Require status checks to pass before merging → add
`adversarial-review`); until then the gate only reports. The pull
request template (`.github/pull_request_template.md`) asks the author
the same questions; the reviewer checks the answers, not just their
presence.

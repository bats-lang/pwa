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

No pull request merges before an adversarial review. The review is a
comment on the pull request, written by someone other than its author
(another agent or a person; agents here post under one account, so the
comment names its reviewer). Its first line is `## Adversarial review`,
and it holds a line `Verdict: approved` or `Verdict: changes needed`.

* **A bug fix** (pwa deviates from its spec: current functionality that
  misbehaves, see "Changes to pwa"): the review confirms it really is a
  deviation from the spec, and that the fix is minimal. Then the pull
  request is fine.
* **A new capability** (a Capacitor plugin, native connectivity, native
  code pwa generates, a new platform): the review answers, with
  evidence (code, measurements, the platform's documentation):
  1. Is there no way to do this with what exists (bridge's atoms and the
     app's own Bats), at reasonable performance?
  2. Is this the minimal wrapper? Does it map 1:1 to the platform API,
     and if not, why can it not be broken into smaller pieces, each a
     bridge atom?
  3. Does the native side decide anything? It may only hand an event or
     a value to one of bridge's entry points (`batsNative`) and read its
     answer, as `MainActivity.java` does.

  The review analyzes the plausible alternatives and says why each
  would not work: a bridge atom on the web API the WebView already
  has, an existing entry point, the app doing it in Bats.
* **Process, documentation or CI** changes add no capability: the review
  confirms they do not.

App policy (which attributes, roles, defaults, when) never lives in
pwa's generated native code or page: it is the app's, in Bats
(bats-lang/pwa#49). A pull request that puts policy in pwa gets
`Verdict: changes needed`.

The gate is `.github/workflows/review-gate.yml`: on every pull request
event and every comment, it finds the newest review comment (the first
line and a verdict line above) and sets the commit status
`adversarial-review` on the pull request's head commit, success only
for `Verdict: approved`, pending otherwise. The gate does not tie a
verdict to a commit (a push keeps the newest verdict), so a pull request
changed after its approval is reviewed again, in a new comment, before
it merges. The pull request template
(`.github/pull_request_template.md`) asks the author the same
questions; the reviewer checks the answers, not just their presence.
`adversarial-review` is a required status check of `main`'s branch rule.

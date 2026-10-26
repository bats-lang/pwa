# pwa

PWA (Progressive Web App) shell generator for [Bats](https://github.com/bats-lang) WASM applications.

## Features

- Generate `index.html` with loading spinner, bridge JS, and service worker registration
- Generate `service-worker.js` for offline caching
- Generate `manifest.json` for PWA metadata
- Uses the `bridge` package to embed the JS bridge source

## Usage

```bats
#use pwa as P
#use builder as B

val html = $B.create()
val () = $P.build_html(html, "My App", "output.wasm")

val sw = $B.create()
val () = $P.build_service_worker(sw, "output.wasm")

val mf = $B.create()
val () = $P.build_manifest(mf, "My App")
```

## gen-pwa test

An app's generator runs its Playwright suite against the built PWA when
its first argument is `test` (bats-lang/pwa#82):

```bats
implement main0 () =
  if $P.test_wanted () then
    (let val s = $P.test_run () in if s <> 0 then exit_void (s) else () end)
  else generate ()
```

`gen-pwa test [--timings <dir>] [--evidence <dir>] [-- <playwright args>]`:

- serves `dist/pwa` on 127.0.0.1 at a port it chooses and gives
  Playwright its address in `PWA_TEST_BASE_URL` (a config reads its
  `baseURL` from it, and leaves out `webServer` when it is set); the
  server goes when the run ends, however it ends;
- takes the machine's lock: `PWA_TEST_SLOTS` runs at once (default 1),
  lock files in `PWA_TEST_LOCK_DIR` (default `~/.cache/pwa-test`), and
  says when it waits;
- checks that `PLAYWRIGHT_BROWSERS_PATH` (else Playwright's default)
  holds the headless Chromium the project's Playwright expects, and says
  which revisions it has when not; it never downloads;
- refuses a Playwright older than 1.58 (bats-lang/pwa#92), saying what to
  install: before it the fake clock (`page.clock`) could set the time
  back after `fastForward`, so a test that counts time failed now and
  then. The floor is the same for every app; an app that needs a newer
  Playwright says so in its `package.json`, as npm enforces it. A
  version it cannot read is refused too;
- watches every page of the tests for a hang (bats-lang/pwa#132, #230),
  with nothing in a spec or a config: a page that does not answer in 5 s,
  or a test within 15 s of its timeout, leaves `<dir>/<project>-<test>-<n>.json`
  (default `pwa-evidence`; the V8 pause frames or a CPU profile, the page's
  recent console, errors and requests, the runner's load) and a line
  `gen-pwa test: hang evidence: <file> (<reason>)`. Upload the directory
  as you upload `--timings`'. What it could not take reads `not available: <why>`;
  it never fails a test;
- runs the tests tagged `@serial` (`test('...', { tag: '@serial' }, ...)`)
  alone on one worker, then the others on half the cores divided by the
  slots; a `--grep` or `--workers` of yours makes it one run, as given;
- with `--timings <dir>`, writes Playwright's JSON report of each run to
  `<dir>/serial.json` and `<dir>/parallel.json` (`<dir>/run.json` for a
  run as given); without it, your own reporters and
  `PLAYWRIGHT_JSON_OUTPUT_NAME` are left alone.

`PWA_TEST_PLAYWRIGHT` names the Playwright to run (default
`node_modules/.bin/playwright`).

## Android app

`create_android(app_name, app_id, web_dir, project_dir)` writes a
[Capacitor](https://capacitorjs.com) project in `project_dir` around the
PWA in `web_dir` (relative to `project_dir`, e.g. `"../pwa"`):
`capacitor.config.json`, `package.json`, `android-release.gradle`,
`build-android.sh` and `fetch-pnpm.sh`. With Node (22 or 24, which ship corepack), a JDK 21
and the Android SDK (`ANDROID_HOME`), `sh <project_dir>/build-android.sh`
builds a release AAB and APK into `<project_dir>/android/app/build/outputs/`.
It installs the packages with pnpm, at the one version it names, through
corepack (`fetch-pnpm.sh`: pnpm's binary is downloaded on first use, so the
first run is retried when the network failed, 3 tries, and the wrapper and
the binary are checked against pinned checksums, bats-lang/pwa#158; pnpm installs a plugin from a subfolder of a git repository,
which npm cannot: bats-lang/quire#321), with `node_modules` flat
(`nodeLinker: hoisted` in the `pnpm-workspace.yaml` it writes), where
Capacitor's Gradle files look for the plugins. In the locked form
(`create_android_locked`, beside `create_android`, which keeps a bare
`pnpm install` until bats-lang/pwa#165 removes it) the install is
`pnpm install --frozen-lockfile` from the `pnpm-lock.yaml` the app
commits and puts beside `build-android.sh` (it is not generated, so what
pnpm resolves for the plugins' own dependencies cannot move under a
commit): the script stops without one, and the install fails on a lock
that does not match the generated `package.json`, without rewriting it.
The lock is made in a clean directory holding that `package.json` and a
`pnpm-workspace.yaml` of `nodeLinker: hoisted`, by `corepack pnpm@12.9.1
install --lockfile-only`; it is made again when bridge's plugin table
changes `package.json` (the example's is `example/pnpm-lock.yaml`). CI checks that the APK
registers exactly the plugins `package.json` installs, each with its
class in the APK.

The activity (`MainActivity.java`) hands the page the files the app is
opened with or shared (VIEW, SEND), each intent's once: Capacitor's
`BridgeActivity.onCreate` hands the launch intent to `onNewIntent`
(its `load()`), and an intent handed over before is not handed over
again when the activity is recreated or started from the recent apps
(`tests/android/activity.sh` runs it against Capacitor's activity). It
also hands over the volume keys, which a
WebView never gives the page: each is offered to it as the `keydown` a
browser sends (`AudioVolumeUp`, `AudioVolumeDown`). A page that takes
one (`preventDefault`, say to turn a page) has it; otherwise the volume
changes, as the key would have changed it.

An address the app is opened at that is not a file (a VIEW intent whose
data is not `content:` or `file:`, such as an OAuth sign-in coming back
at the app's own scheme) is left to Capacitor's App plugin, which
bridge's `listen_app_link` passes to the page, and it too is handed
over once: the intent `load()` hands over again on a recreation does
not reach Capacitor's plugins either. The scheme's intent filter is the
app's to write into `intent-filters.xml`, after `build_intent_filters`'
own (as quire's `gen-pwa` does).

Signing: set `ANDROID_KEYSTORE` to a keystore file and
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`;
without `ANDROID_KEYSTORE` the build is unsigned. `ANDROID_VERSION_CODE`
sets the version code (default 1). No secret is ever written to a file
by the generator.

In CI, upload the project and PWA directories as an artifact and call
the reusable workflow, which decodes the keystore from the caller's
secrets `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS` and
`KEY_PASSWORD`, and uploads the artifacts `release-aab` and
`release-apk`:

```yaml
  android:
    needs: build
    uses: bats-lang/pwa/.github/workflows/android.yml@main
    secrets: inherit
    with:
      artifact: my-app-android   # holds android/ and pwa/
      project-dir: android
      version-code-offset: 0     # version code = run number + this
      smoke-test-text: Hello     # optional: run it on an emulator
```

With `smoke-test-text`, a second job boots an Android emulator (API 34,
hardware-accelerated on the Linux runner), installs the APK, launches it
and waits for that text on the screen: pick one only the app's wasm
renders, so the test shows the wasm ran. It fails when the text never
shows, the app crashes, or the page logs a console error, and uploads
the artifact `android-smoke-test` (a screenshot, the UI dump and the
logcat). With `smoke-share-file` (a file in the artifact),
`smoke-share-type` and `smoke-share-text`, it then starts the app anew
with that file (VIEW) until that text shows, turns and recreates it,
and opens and shares the file with it while it is open (VIEW, SEND):
it fails unless each intent's file is handed to the page once. The
project's `smoke-test.sh` does the work and runs against any device
`adb` sees.

### The signing key's fingerprints, and Play's

With a signing key, `android.yml` can print the key's SHA-1 and SHA-256
fingerprints in the job log and summary (`scripts/key-fingerprints.sh`,
by `keytool`; the password is handed to it by environment variable, and
no password or key material is printed). Pass `pwa-ref`, the commit you
call the workflow at (a reusable workflow cannot read it, so the script is
taken from the commit you name, as for `play-release.yml`):

```yaml
    with:
      pwa-ref: <sha>                 # prints the upload key's fingerprints
      play-signing-sha1: 5A:48:...   # optional: Play's app signing SHA-1
```

Play re-signs what you upload with its own app signing key, so an app
installed from Play carries Play's certificate, not the upload key's. An
Android OAuth client (Google sign-in, Drive) is matched by package and
SHA-1: register the upload key's SHA-1 for a sideloaded build and Play's
for the installed one. The mistake of registering the upload key's SHA-1
where Play's belongs signs in on the APK and fails only on the Play
install (bats-lang/quire#200). With `play-signing-sha1` (Play Console,
Protected with Play, Play app signing, App signing key certificate) the
job fails when it is the upload key's SHA-1, is not a SHA-1 fingerprint
(`AA:BB:...`, 20 bytes; either case), or is given without `pwa-ref` or a
signing key. Without the input nothing is checked and nothing changes;
without `pwa-ref` the fingerprints are not printed.
`tests/key-fingerprints/run.sh` checks the script on keystores it makes.

## Releasing to Google Play

`android.yml` builds, signs and checks the AAB and uploads it as
`release-aab`. `.github/workflows/play-release.yml` releases that
artifact to a track of Google Play, the internal testing track unless
told otherwise, through the Play Developer API's edits
(`scripts/play-release.sh`: insert an edit, upload the bundle, set the
track to a completed release of the bundle's version code with the
notes, commit with `ERROR_IF_IN_REVIEW`; an edit that does not commit is
deleted, so none is left half made). It signs in by Workload Identity
Federation, so no key is stored anywhere: GitHub's OIDC token is
exchanged for a token of a service account.

```yaml
  play-internal:
    needs: android
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    uses: bats-lang/pwa/.github/workflows/play-release.yml@<sha>
    permissions:
      contents: read
      id-token: write
    with:
      pwa-ref: <sha>                  # the same full SHA as the pin above: the script is taken from it
      package: dev.example.app
      workload-identity-provider: projects/<number>/locations/global/workloadIdentityPools/<pool>/providers/<provider>
      service-account: <name>@<project>.iam.gserviceaccount.com
```

`pwa-ref` must be the same full 40-hex SHA as the `uses:` pin of the
caller, never a branch or a tag: a reusable workflow cannot read the
commit it was called at, so `pwa-ref` alone says which `scripts/` run, and
a different or floating value runs a script other than the pinned one. A
caller that lets the two differ has chosen that skew itself.

Inputs: `artifact` (default `release-aab`), `track` (`internal`, `alpha`,
`beta` or a custom closed track's name; `production` is refused),
`notes` (at most 500 characters; by default the first line of the
pushed commit's message, cut to 500 at a whole character) and `dry-run`
(validate the edit and delete it). The release is named by Play from the
bundle's `versionName`; its version code must be higher than every
earlier upload's (`android.yml`'s run number plus `version-code-offset`).
Releases of one package and track take turns. The provider and the
service account are public names, not credentials. `scripts/play-release.sh`
can be run by hand with `PLAY_ACCESS_TOKEN`, `PLAY_PACKAGE` and
`PLAY_TRACK`; `tests/play-release/run.sh` checks it against a stub of
Play.

### What the app's owner sets up

1. **Play Console.** The app exists, with its first release uploaded by
   hand (the API cannot create an app), and Play App Signing is on.
2. **A Google Cloud project** with the *Google Play Android Developer
   API* enabled, a service account in it (no Cloud IAM role is needed),
   and a Workload Identity pool with a GitHub OIDC provider
   (issuer `https://token.actions.githubusercontent.com`). Map
   `attribute.repository = assertion.repository`, and give the provider
   an attribute condition that admits only the runs that may release,
   for example
   `assertion.repository == 'OWNER/REPO' && assertion.ref == 'refs/heads/main' && assertion.event_name == 'push'`.
   Without a condition, any workflow of any repository that knows the
   provider's name could ask for the account's token. Let the pool's identities of that repository impersonate the service
   account (`roles/iam.workloadIdentityUser` on the account for
   `principalSet://iam.googleapis.com/projects/<number>/locations/global/workloadIdentityPools/<pool>/attribute.repository/OWNER/REPO`).
   The `repository`, `ref` and `event_name` claims are the *calling*
   workflow's, even though the job runs in this reusable workflow
   (`job_workflow_ref` is the one that names this file), so a condition
   on the calling repository works, and it is where "main only" is
   enforced: the caller's `if` is only a convenience. To pin releases
   to this workflow as well, add a condition on `job_workflow_ref`
   (the path of this file with the ref the caller's `uses:` names, for
   example `assertion.job_workflow_ref == 'bats-lang/pwa/.github/workflows/play-release.yml@<sha>'`)
   or on `job_workflow_sha` (the commit of this file); a caller that
   copies the job or points at another version of the workflow then
   gets no token, and moving the pin means changing the condition in
   the same step. Such a condition pins the workflow file only: the
   script that runs comes from the commit named by `pwa-ref`, which the
   condition does not pin. GitHub documents both claims: "the ref path to the
   reusable workflow" and "the commit SHA for the reusable workflow
   file"
   (https://docs.github.com/en/actions/reference/security/oidc);
   Google's attribute conditions can use any claim the provider
   maps or reads from `assertion`
   (https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines).
3. **Play's user management** (Users and permissions, then Invite new
   users): the service account's address, with the permission *Release
   apps to testing tracks* for this app and nothing else. Production
   releases stay a person's step.
4. The caller grants `id-token: write` to the job (a called workflow
   cannot widen its caller's permissions).

### Internal testing first, then production

Every release goes through the internal testing track before
production. Then:

1. Install the release from Play on a test device, as a tester, not by
   sideloading. A device with the production app installed needs no
   uninstall: Play updates it in place.
2. Check what the release changed on that device. Play signs the
   release with the *app signing key*, as production is, so anything
   tied to the signing certificate (Google sign-in, an OAuth client
   registered with a SHA-1) behaves as it will in production. The
   `release-apk` artifact is signed with the *upload key* instead, and
   Google refuses such a sign-in (`DEVELOPER_ERROR`) when the client is
   registered with Play's app signing SHA-1; keep it for quick checks
   that involve nothing tied to the key.
3. Promote that same release to production in the Play Console.

## Example

See `example/` for a complete project that builds a PWA:

```bash
cd example
bats lock --repository ../repository-prototype
bats build --repository ../repository-prototype
bats run --bin build-pwa --repository ../repository-prototype
# → dist/pwa/ contains the ready-to-serve PWA,
#   dist/android/ the Capacitor project (sh dist/android/build-android.sh)
```

## API

See [docs/lib.md](docs/lib.md) for the full API reference.

## Safety

Safe library — `unsafe = false`.

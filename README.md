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

## Android app

`create_android(app_name, app_id, web_dir, project_dir)` writes a
[Capacitor](https://capacitorjs.com) project in `project_dir` around the
PWA in `web_dir` (relative to `project_dir`, e.g. `"../pwa"`):
`capacitor.config.json`, `package.json`, `android-release.gradle` and
`build-android.sh`. With Node (22 or 24, which ship corepack), a JDK 21
and the Android SDK (`ANDROID_HOME`), `sh <project_dir>/build-android.sh`
builds a release AAB and APK into `<project_dir>/android/app/build/outputs/`.
It installs the packages with pnpm, at the one version it names, through
corepack (pnpm installs a plugin from a subfolder of a git repository,
which npm cannot: bats-lang/quire#321), with `node_modules` flat
(`nodeLinker: hoisted` in the `pnpm-workspace.yaml` it writes), where
Capacitor's Gradle files look for the plugins. CI checks that the APK
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

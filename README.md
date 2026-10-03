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
`build-android.sh`. With Node, a JDK 21 and the Android SDK
(`ANDROID_HOME`), `sh <project_dir>/build-android.sh` builds a release
AAB and APK into `<project_dir>/android/app/build/outputs/`.

The activity (`MainActivity.java`) hands the page the files the app is
opened with or shared (VIEW, SEND), and the volume keys, which a
WebView never gives the page: each is offered to it as the `keydown` a
browser sends (`AudioVolumeUp`, `AudioVolumeDown`). A page that takes
one (`preventDefault`, say to turn a page) has it; otherwise the volume
changes, as the key would have changed it.

`create_android_linked(..., mime, scheme)` writes the same project for
an app that is also opened at addresses of its own scheme
(`scheme://...`), as an OAuth sign-in in the system browser comes back
to a native app (RFC 8252's private-use URI scheme): the activity gets a
VIEW intent filter for it. Such an address is not a file: the activity
leaves it to Capacitor's App plugin, which bridge's `listen_app_link`
passes to the page.

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
logcat). The project's `smoke-test.sh` does the work and runs against
any device `adb` sees.

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

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

## Example

See `example/` for a complete project that builds a PWA:

```bash
cd example
bats lock --repository ../repository-prototype
bats build --only native --only debug --repository ../repository-prototype
bats run --only debug --bin pwa --repository ../repository-prototype
# → dist/pwa/ contains the ready-to-serve PWA
```

## API

See [docs/lib.md](docs/lib.md) for the full API reference.

## Safety

Safe library — `unsafe = false`.

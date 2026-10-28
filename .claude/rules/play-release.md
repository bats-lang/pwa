---
paths:
  - .github/workflows/play-release.yml
  - scripts/play-release.sh
  - tests/play-release/**
---

# The Play release workflow (pwa#90, quire#623)

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

* **The new version code is above every code on Play (pwa#258, keyword:
  version-code).** In the same edit, before the upload, the script reads the
  track (`edits.tracks.get`) and the bundles (`edits.bundles.list`); after
  the upload, which is where Play names the new bundle's code (it is in the
  bundle's manifest, a protobuf), and before the track is set, it refuses a
  code that is not strictly above the highest of the two, naming the new code
  and the highest. Nothing is kept in a file: the data is the run's own. The
  edit is deleted as for any refusal. An empty track and no bundles accept
  any code. `tests/play-release/run.sh` plays equal (the 955894 case), lower,
  higher and empty against the stub (`STUB_TRACK_CODES`, `STUB_BUNDLE_CODES`,
  `STUB_UPLOAD_CODE`).
* **Play's answer shapes (pwa#258; read 2026-10-28).** The Google Play
  Developer API reference says, for `edits.tracks.get` (a `Track`, whose
  `releases[]` are `Release`s): `versionCodes[]` is `string ( int64 format)`,
  "Version codes of all APKs in the release"
  (https://developers.google.com/android-publisher/api-ref/rest/v3/edits.tracks);
  for `edits.bundles.list` (`{"kind": string, "bundles": [Bundle]}`): a
  `Bundle`'s `versionCode` is `integer`, "The version code of the Android App
  Bundle, as specified in the Android App Bundle's base module APK manifest
  file" (https://developers.google.com/android-publisher/api-ref/rest/v3/edits.bundles).
  The script applies `tonumber` to both, so it takes either form; the stub
  writes strings for the track and numbers for the bundles, as the reference
  says. No recorded real answer was found in this repository's history.
* **Why this is shell, jq and Python (the avenue, pwa#258, CLAUDE.md "We do
  not write shell scripts").** The job is an HTTPS call with a bearer token
  (`edits`, `tracks`, `bundles`), a comparison of the numbers in the answers,
  and, for the test, a loopback HTTP server that logs each request. Searched
  in the bats packages (2026-10-28; `grep -E "socket\(|getaddrinfo|SSL_|
  libcurl|curl_|accept\(|listen\("` over every package's `.bats` sources):
  no package opens a socket, speaks TLS or serves HTTP. `process` spawns a
  program, so a bats program could only run `curl`, which is the same
  dependency with a bats wrapper; `json` and `toml` parse, they do not
  call; `bridge`'s `fetch` is wasm only (`#target wasm`); `file` reads
  files and descriptors. What bats lacks is a native HTTPS client and a
  loopback HTTP server; the move is bats-lang/repository-prototype#543 (p2).
  The script and its test already existed as shell; this change adds a
  comparison to them, not a new file.
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
  `pwa-ref` must be the same full SHA as the caller's `uses:` pin, never a
  branch or a tag: a different or floating value runs a script other than
  the pinned one. Skew between the two is the caller's choice, not an
  escalation.
* **Who may release is Google's side, not this workflow's.** The provider's
  attribute condition (the calling repository, the ref, the event) admits
  the runs that get the service account's token; the workflow checks
  nothing of the kind, and the README says what the app's owner sets up.
  The token's `repository` claim is the caller's in a reusable workflow
  (`job_workflow_ref` names this file), so a condition on the calling
  repository holds.
* **The notes are made by the script (pwa#195).** With `-` for the notes
  file, `scripts/play-release.sh` takes `NOTES` whole when it is not empty,
  else the first line of `COMMIT_MESSAGE`, trims it and cuts it to 500
  characters; the workflow only passes the two as environment. So
  `tests/play-release/run.sh` runs that logic (the first line, the cut, the
  given notes whole) and also asserts the job's `permissions:` are `contents:
  read` and `id-token: write`. The notes-file form stays and is tested.
* **Inputs reach the shell as environment variables**, never spliced into a
  script, so a commit message cannot inject into the step.
* Pins (by commit, verified with `git ls-remote` on the tag):
  `actions/checkout` v4, `actions/download-artifact` v4,
  `google-github-actions/auth` v3.0.0.
* The first run is an app's: the workflow needs Google, so only an app's
  push to main exercises it end to end (its `dry-run` input validates the edit
  and releases nothing).

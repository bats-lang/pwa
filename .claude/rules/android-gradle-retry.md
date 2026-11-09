---
paths:
  - tools/android-sdk-pins/**
  - .github/workflows/android.yml
---

# The Android build runs again on a dependency resolution failure (pwa#276)

quire#1032 was removed from quire's merge queue after 44 minutes by one
failed build of `android.yml` (run 41539786486, job 125620450802, step
"Build release AAB and APK", 23:28:26 to 23:28:42, 2026-11-02): Gradle,
configuring the root project, answered `Could not find
org.jetbrains.kotlin:kotlin-stdlib:2.2.0` (and many more modules, such as
`org.apache.httpcomponents:httpmime:4.5.6`), "Searched in" dl.google.com and
repo.maven.apache.org, which publish them. The same head had passed on its
pull request run.

* **Cause, from that log.** The cache step said `Cache not found for input
  keys: android-downloads-Linux-2026-11-...`: the key carries the month, and
  this was the first build of November, so no Maven artifact was on the runner
  and every one came from the network, in the 15 seconds between "Starting a
  Gradle Daemon" and the failure. The repositories failed to answer for
  those modules (the log has no response code: Gradle prints none without
  `--info`, only "Could not find", which is what it says for a not-found
  answer and not for a timeout, "Could not GET"). Nothing in the project
  changed between the two runs.
* **The retry.** The step "Build release AAB and APK" stays one step, whose last
  line calls the tool `android-sdk-pins build-again LOG PROGRAM [ARGUMENT]`
  (`tools/android-sdk-pins/src/bin/android-sdk-pins.bats`, which is bats; the
  step adds no shell, and its version code, secrets and `shell: bash` are as
  they were). The tool runs `build-android.sh` (through `env`, so it is found on
  `PATH`, with the environment inherited) at most `ANDROID_BUILD_ATTEMPTS` times
  (default 3, 1 to 9). It runs again only when the attempt's output says a
  dependency was not found, not resolved or not downloaded, or names a timeout
  or reset connection (`grep -Eq`, the ERE in the tool); every other failure
  ends the command with 1 at once, and so does the failure of the last attempt,
  which fails the step (there is no later decision). A pass ends it with 0.
  Each retry is a `::warning::` line on stdout that names the attempt.
* **Where the output lands.** Each attempt's stdout and stderr, merged, are
  written to `$RUNNER_TEMP/build-android.log.attempt` (emptied first) and then
  written to the job log and appended to `$RUNNER_TEMP/build-android.log`, so the
  log holds every attempt in order, for "Say why the build failed". An attempt's
  output reaches the job log when that attempt ends, not line by line. That is
  accepted.
* **The job order.** `build-android` needs `sdk-pins-tool`, which now runs for
  every caller (it had run only with a smoke test), a cost of about 72 s on the
  build's critical path; the ruling on pwa#277 accepted it.
* **Why the caches are cleared.** Gradle remembers a repository's not-found
  answer for 24 hours, so the same job would have asked nobody again. Before
  the next attempt the tool stops the Gradle daemon (`./gradlew --stop` in
  `GRADLE_PROJECT`, its status said and not judged) and removes
  `$HOME/.gradle/caches/modules-2/metadata-*`; the downloaded files
  (`files-2.1`) stay. It then pauses `ANDROID_BUILD_PAUSE_S` seconds (default 30).
* **The tests** (`tools/android-sdk-pins/src/smoke_tests.bats`, run by `bats
  test` in the step "SDK pins tool" of `check`) run the built tool against a
  stand-in build (`src/bin/build_stand_in.bats`, the build script and the
  Gradle wrapper of each case): `build-flaky` (a first failed fetch with
  Gradle's text, then a pass: the tool exits 0, the warning names attempt 1 of
  3, Gradle is stopped, the metadata cache is gone and the downloaded file
  stays), `build-other-failure` (one attempt, exit 1, nothing stopped),
  `build-always` (three attempts, exit 1), `build-at-once`, `build-usage` and
  `build-merged`. The step's lines are compared with
  `tools/android-sdk-pins/tests/build-wiring.txt` the way the emulator step's
  are with `tests/wiring.txt` (a deleted, changed, added or swapped line, and a
  bounding line absent, repeated or out of order, are refused). The step itself
  needs an app's artifact and runs in an app's job.

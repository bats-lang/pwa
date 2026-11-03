---
paths:
  - tests/android-gradle-retry/**
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
* **The retry.** The build step runs `build-android.sh` at most 3 times. It
  runs again only when the output says a dependency was not found, not
  resolved or not downloaded, or names a timeout or reset connection; every
  other failure ends the step at once. Each retry is a `::warning::` that
  names the attempt, and `build-android.log` (which "Say why the build
  failed" reads) holds every attempt.
* **Why the caches are cleared.** Gradle remembers a repository's not-found
  answer for 24 hours, so the same job would have asked nobody again. Before
  the next attempt the Gradle daemon is stopped and `modules-2/metadata-*` is
  removed; the downloaded files (`files-2.1`) stay.
* **Not a dependency cache keyed by the locked versions.** The existing
  `android-downloads-*` cache is kept: it is saved after a build that passed
  and restored under its exact key, so a new month or a changed project
  starts empty; the retry covers that first build.
* `tests/android-gradle-retry/check.sh` (a step of `check`) runs the lines of
  the step between `# retry-begin` and `# retry-end`, taken from the workflow,
  against a stand-in build that fails once with Gradle's text and then
  passes, one that fails otherwise, one that always fails resolving, and one
  that passes. The step itself needs an app's artifact and runs in an app's
  job.

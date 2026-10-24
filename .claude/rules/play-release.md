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

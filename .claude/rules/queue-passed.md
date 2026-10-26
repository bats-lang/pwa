---
paths:
  - .github/actions/queue-passed/**
  - tools/queue-passed/**
  - tests/queue-passed/**
---

# Skipping a push run's tests when the merge queue passed the same commit (pwa#215)

Process (CI) tooling, not something pwa generates or an app runs.

* **The problem** (quire#879, quire#869's entry removed three times at the 60-minute limit): a merge
  queue fast-forwards main to the group's commit, so a push run of main tests a commit a `merge_group`
  run has already passed, and it runs while the next entry's group is being tested, on the same 20
  runners (253 job-minutes cold, against 144 for the group's run). 25 of quire's last 30 push runs
  had a passed `merge_group` run on the very same sha.
* **The action** (`.github/actions/queue-passed`) answers `skip` (`true` or `false`), `run-url` and
  `reason`. An app calls it by commit in the job that plans its tests, after the checkout, with
  `permissions: {actions: read, contents: read}`, and takes its static and e2e groups from `skip`: a
  group it skips is a job that ends after its first step (so the aggregate `check` still passes as
  itself, and a workflow whose jobs are all skipped is not `skipped`), and its aggregate prints
  `run-url` as the reason the group was not run again. What ships (the app's build and signing, the
  Android build and smoke test, the Play release) never reads it. On any event but `push` the action
  does nothing and says `skip=false`, so a schedule (the nightly cold check of main), a
  `workflow_dispatch` and a pull request always run everything.
* **What the app owes:** the skip is sound when the queue's run tested what the push run would. quire's
  queue run runs every group (its own rule, quire#656); an app whose queue run selects fewer groups than its
  push run does not skip those the queue did not run.
* **The decision is by the commit and the API's answer alone.** `tools/queue-passed` (a bats binary:
  no shell of ours decides) reads `gh api repos/R/actions/runs?event=merge_group&head_sha=SHA` from a
  file and skips only when a run in it has, each read from the run itself and not from the query's
  filters, event `merge_group`, `head_sha` equal to the pushed sha, `path` equal to the workflow file
  of `github.workflow_ref` (between its second slash and its `@`) and conclusion `success`. No time,
  no cache key and no name is compared. `skipped` (what the queue's `destroyed` event's run ends with,
  quire#879 run 40243573211), `cancelled`, `failure`, a run with no conclusion yet, a run of another
  workflow file (`supersede.yml` passes on the same sha), another sha, another event, a sha that is
  not 40 lower case hex digits, a workflow ref that names no file, and an answer that is missing,
  empty, over 1048576 bytes (an array of exactly the file's size, which `alloc` caps), not JSON or not
  an object all run everything. A failed call of the API leaves no usable file and runs everything.
  Only the first 20 runs of the sha are asked for: more than that on one commit is not seen, which
  can only run more.
* **Steps of the action:** `gh api` (one third-party command), the bats setup action as the caller's
  pins say (`.github/bats-version`, `.github/repository-version`, `bats.lock` of the caller; it is
  the setup the caller's own `build` job runs), `bats build --only release` of the tool from the
  action's own commit (`github.action_path`), and one call of the tool whose stdout is appended to
  `GITHUB_OUTPUT`. A push run pays that setup in its plan job; the other events pay nothing.
* **Tests:** `tests/queue-passed/check.sh` drives the built tool over `tests/queue-passed/answers`,
  GitHub's own answers (README there), one case for each class above and each with the exact reason
  it must give, so a case cannot pass by running everything for another cause; the pwa check runs it
  (`queue-passed tool`) and runs the action itself on a fixture (`queue-passed-action`). The
  injections the ticket asks for were made by editing the tool: the sha comparison dropped fails
  `other-sha` and `other-sha-one-digit`; `skipped` taken as a pass fails `skipped`, and `passed` too
  (the destroyed run is listed before the passing one); the path, event and conclusion comparisons
  dropped each fail their own fixture.
* **Shell, and why:** `check.sh` is shell because it drives a built binary against files
  (`tests/android-sdk-pins/check.sh` is the precedent); the action's `run:` steps each call one
  third-party tool or one bats command, and the two `test` lines of the action's test job compare an
  output (GitHub Actions has no assertion step).

## What others do (searched for pwa#215)

* Excluding the queue's branches from the push trigger (`branches-ignore: gh-readonly-queue/**`,
  redhat-et/ProtoBot#312, and a community discussion that reports it working): that stops a push
  run of the *queue branch*, which pwa's apps never had (their `push` is `branches: [main]`); it does
  not touch the push run of main.
* jikig-ai/soleur#9512 is the same question: "skip the duplicate push-to-main CI run when a
  merge_group run already passed on the same SHA", measured 13 of 15 push runs with a passed
  `merge_group` run on the same sha ("by construction" for a squash queue), with the same warnings
  taken here: direct pushes, `--admin` and bypass merges build commits no group ran, so the skip
  is "keyed per SHA" and "never a static removal of the push run"; the deploy needs a push run with a
  passing conclusion, so the push run stays and its tests are skipped inside it; and a run whose jobs
  are all skipped concludes `skipped`, so a real job must remain.
* cariad-tech/merge-queue-ci-skipper skips CI for a PR enqueued into an empty queue, up to date with
  its base; it asks the branch protection settings (`administration:read`) which checks are required,
  and says it is untested. Here the question is answered by the commit and the runs, which need only
  `actions: read`.
* GitHub's documentation of the merge queue says the queue merges the group's changes into the base
  branch once the required checks pass; it does not say the base is fast-forwarded to the group's
  commit. The evidence for it is the repository's: all 25 push runs of quire's `check` since the
  queue began have a `merge_group` run on their sha, and a push of a commit with no such run gets no
  skip.

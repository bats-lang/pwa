# pwa

PWA (Progressive Web App) shell generator for [Bats](https://github.com/bats-lang) WASM applications.

## Android app

### The signing key's fingerprints, and Play's

Play re-signs what you upload with its own app signing key, so an app
installed from Play carries Play's certificate, not the upload key's. An
Android OAuth client (Google sign-in, Drive) is matched by package and
SHA-1: register the upload key's SHA-1 for a sideloaded build and Play's
for the installed one. The mistake of registering the upload key's SHA-1
where Play's belongs signs in on the APK and fails only on the Play
install (bats-lang/quire#200).

## Releasing to Google Play

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

## API

See [docs/lib.md](docs/lib.md) for the full API reference.

## Safety

Safe library — `unsafe = false`.

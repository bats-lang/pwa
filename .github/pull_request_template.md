## What and why

<!-- What changes, and the issue or spec it answers. -->

Kind: <!-- one of: bug fix / new capability / process, documentation or CI -->

## Bug fix

<!-- Delete this section unless Kind is "bug fix". -->

- The current functionality that misbehaves, and the spec it deviates from:
- Why this is the minimal fix:

## New capability (a plugin, native connectivity, generated native code, a new platform)

<!-- Delete this section unless Kind is "new capability". Answer each with evidence: code, measurements, the platform's documentation. -->

1. Is there no way to do this with what exists (bridge's atoms and the app's own Bats), at reasonable performance?
2. Is this the minimal wrapper? Does it map 1:1 to the platform API? If not, why can it not be broken into smaller pieces, each a bridge atom?
3. Does the native side decide anything, or does it only hand an event or value to one of bridge's entry points (`batsNative`) and read its answer?
4. The plausible alternatives, and why each would not work:
5. Where the app's policy (which attributes, roles, defaults, when) lives: it must be in the app's Bats, not in pwa's native code or page (bats-lang/pwa#49).

## Review

No merge before an adversarial review: a comment by someone other than the author, first line `## Adversarial review`, with a line `Verdict: approved` or `Verdict: changes needed` (CLAUDE.md, "Adversarial review before merge"). The `adversarial-review` status follows the newest one.

## What and why

<!-- What changes, and the issue or spec it answers. -->

Kind: <!-- one of: bug fix / new platform / process, documentation or CI. pwa takes no other change ("Changes to pwa" in CLAUDE.md); the review confirms the kind from the diff. -->

## Bug fix

<!-- Delete this section unless Kind is "bug fix". -->

- The current functionality that misbehaves, and the spec it deviates from:
- Why this is the minimal fix:
- That it adds no native behaviour, plugin, JS handler or DOM write, and puts no policy in pwa:

## New platform (iOS, Electron, …)

<!-- Delete this section unless Kind is "new platform". Answer each with evidence: code, measurements, the platform's documentation. A plugin, native connectivity or generated native code for a feature is not accepted: it is a bridge atom and the app's own code. -->

1. Is there no way to do this with what exists (bridge's atoms and the app's own Bats), at reasonable performance?
2. Is this the minimal wrapper? Does each native piece map 1:1 to the platform's API? Why can it not be broken into smaller pieces, each a bridge atom? (Always answer; in detail when it is not 1:1.)
3. Does the native side decide anything, or does it only hand an event or value to one of bridge's entry points (`batsNative`) and read its answer? Does anything of pwa's write to the DOM? (It must not: that is a bridge stream opcode issued by the app.)
4. The plausible alternatives, and why each would not work:
5. Where the app's policy (which attributes, roles, defaults, when) lives: it must be in the app's Bats, not in pwa's native code or page (bats-lang/pwa#49).

## Review

No merge before an adversarial review (CLAUDE.md, "Adversarial review before merge"): a new comment in this conversation by a trusted author (OWNER, MEMBER or COLLABORATOR) other than the PR's author. Its first line is exactly `## Adversarial review`; it has exactly one line `Verdict: approved` or `Verdict: changes needed` and exactly one line `Reviewed: <full head SHA>`, both exact; it is plain text and inline code only (no code fences, no HTML, ASCII letters). The newest review attempt alone sets the `adversarial-review` status: success only for an unedited, perfectly formed approval of the current head, with no newer "Request changes" review. A push after approval needs a new review.

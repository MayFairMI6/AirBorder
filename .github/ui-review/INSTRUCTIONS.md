# Handling the UI review queue

`.github/workflows/ui-review-queue.yml` adds one comment to the open **UI review queue** issue (label `ui-review-queue`) for each pull-request commit whose **iOS CI** or **UI review** run failed. Codex or Claude handles each request in a local session. No AI calls run in CI.

For substantive review of passenger-facing changes, including when tests pass,
use [the advisory Codex design review](DESIGN-REVIEW.md). It is separate from
this failure queue and does not change the merge checks.

For each request:

1. Read the failing run and its artifacts: iOS CI uploads `xcresult` with UI-test screenshots and audit failures, and the UI review job log lists missing evidence, copy tags or `Web/` changes.
2. Identify the affected screen and its Figma frame on the Prototype page (`858:8324`, file `zQaZKxZ1rrX4EMYQkY3j00`); see `Documentation/HCI/Figma-code-mapping.md`. Take a screenshot of the current screen.
3. **Image first.** For any visual fix, generate a preview of the proposed fix with `imagegen` or another current image-generation tool, grounded in the failing screenshot and the Figma frame. Keep the original AirBorder phone design: navy/blue/yellow semantic palette, Outfit, existing components and genuine Haneda imagery. Make the smallest change. Show the preview and get the user's approval before changing code or Figma. The preview is never shipped as an asset or cited as implementation evidence.
4. Fix on the pull request's branch. Never skip, delete or loosen tests, audits or assertions, and never regenerate screenshot baselines to make a check pass.
5. Update the PR description: `Preview (approved): <link>` and `Screenshots: <links>` for the fixed screens.
6. Reply on the queue comment with the outcome and the fixing commit, then tick the request off. Close the issue when every request is handled.

Non-visual failures (build errors, flaky infrastructure, missing PR evidence only) need no preview: fix or rerun, and say so in the reply. A missing-preview failure on the gate is resolved by the author adding the approved preview, or the `no-visual-change` label when nothing visible changes.

# Advisory Codex review of passenger-facing design

Review changes to an AirBorder screen, label, alert, default, task sequence,
or passenger-visible state, including pull requests with passing tests. Ask
whether the screen helps a traveler make the right decision even if every
control behaves as specified.

Review the exact PR head. Inspect the task, expected outcome, affected screens
and preceding/following states. Use the acceptance contract in
`Documentation/HCI/Acceptance-and-review.md` and the approved Figma frame or
before/after renderings when available. Say what you observed in a rendering,
what source supports, and what is missing. A predicted misunderstanding is a
hypothesis until tested with a traveler.

Look for a checkpoint action that reads as completed status, an unconfirmed
bag handoff that looks cleared, a gate update that obscures the revised next
action, or a camera-to-map transition that obscures where to resume. Check
whether meaning survives without color and whether instructions identify the
applicable gate, route, airport, or condition. Distinguish defects introduced
or exposed by the change from older observations; avoid unsupported cosmetic
judgments or out-of-scope redesigns.

Return up to three findings, ranked by consequence. For each give:

1. **Severity and type:** critical (plausible safety or clearance error),
   major (task failure or materially wrong next action), or minor (recoverable
   friction); design defect, implementation defect, or evidence gap.
2. **Evidence:** screen, state, visible text or interaction, and screenshot or
   source reference. State what the evidence actually supports.
3. **Traveler consequence:** what a person could reasonably infer or do.
4. **Smallest revision and verification:** what to change and a scenario,
   assertion, or neutral participant question to check it.

If evidence is missing, name the screen/state to inspect. If warranted, say
“no substantive findings in the reviewed evidence.” Do not assign an overall
design score. Review only: no edits, approvals, posting by a local reviewer, or
changes to CI requirements. Visual fixes follow the existing preview approval
process.

## Select a reviewer model using your ChatGPT account

For hosted PR review, use the existing automatic Codex GitHub integration or
request `@codex review`. The repository rules guide the review; they do not
set the hosted reviewer model.

For explicit model selection, open the PR checkout in Codex signed in with
ChatGPT, select an available model, attach the relevant screenshots and ask it
to follow this file. Or run from the checkout using the ChatGPT-signed-in CLI:

```sh
codex exec --sandbox read-only --model gpt-6.1-sol \
  -c 'model_reasoning_effort="high"' \
  --image /path/to/after.png \
  'Review the current PR for passenger-facing design defects. Follow .github/ui-review/DESIGN-REVIEW.md. Review only and return findings here.'
```

GPT-6.1 Sol with high reasoning is a suggested starting point. Choose a
vision-capable model available to your account, and attach a matching before
image or Figma export when available. Record the selected model, PR head and
reviewed evidence. If model identity is unavailable, report it as unknown.

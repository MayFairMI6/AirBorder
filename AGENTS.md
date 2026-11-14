# AirportXRCompanion agent routing

Use the project-scoped custom agents in `.codex/agents/` whenever work is delegated.
Name the role explicitly; do not spawn an unnamed generic agent when one of these roles fits.

Choose the parent by task risk before delegation:

- `parent_deep`: ambiguous, safety-critical, architecture, immigration, privacy/security, licensing, learning, probability, and cross-system decisions.
- `parent_balanced`: normal implementation, UI, backend, and multi-file maintenance with policy already decided.
- `parent_fast`: mechanical searches, builds, tests, logs, formatting, and evidence-only documentation.

When the current root session is already the parent, it follows the same classification. A
fast or balanced parent must escalate when deeper judgment appears; it must not silently keep
the cheaper profile. Use `scripts/run-codex-parent.sh` to pin a new root invocation via CLI
overrides, which have higher precedence than the project default.

- `architect`: architecture, advanced algorithms, migrations, provider/licensing policy, and ambiguous cross-feature decisions.
- `safety_reviewer`: immigration/entry guidance, privacy/security, cache authority, probabilistic safety, and learning-policy review.
- `worker`: bounded implementation after the decision is made.
- `explorer`: read-only repository or log exploration.
- `ui_researcher`: UX research, passenger-flow critique, wireframes, and accessibility rationale.
- `test_runner`: builds, tests, simulator logs, fuzz/replay evidence, and reproducibility checks.
- `docs_reporter`: guides, reports, references, and evidence synchronization.

Deep roles use `gpt-5.6` with `xhigh` reasoning. Routine bounded roles use
`gpt-5.6-terra` with low or medium reasoning. The root session integrates results using
the project default (`gpt-5.6`, high), unless its launch command pins a task parent profile.
Do not let a lower-cost role decide or weaken a safety boundary. A task parent may delegate
one level to a specialist; that specialist must not delegate again. Keep at most four concurrent
threads.

Runtime model, permission, or administrator policy can override repository defaults. If a
pinned model is unavailable, report the failure; do not silently substitute a different model.

## Handoff and continuity

At the start of implementation or after a handoff/context compaction, read the current checkpoint in `.codex/project-context.md` and the relevant acceptance criteria in `Documentation/HCI/Acceptance-and-review.md`. Treat older ledger sections as dated evidence, not current completion claims. Verify the current branch, changes, PR head, checks and unresolved reviews before resuming. Update the checkpoint after material verified progress; preserve decisions, scope, remaining defects and exact evidence. Do not create a second competing `compaction.md` or change compaction configuration merely to store project status. During code review, use the acceptance contract and applicable Code Review Rules; a ledger's statement that tests passed never substitutes for current CI.

## Code Review Rules

### Passenger decisions and state

- Recommendations may change only selected, incomplete, optional stops, and only after explicit Apply. Preserve order, required stops, and user changes across flight/weather updates. Reject stale recommendations after any relevant plan, observation, or clock change; support Undo. Missing, stale, or invalid timing inputs are unknown, never zero or confident permission to proceed. A departure delay must not silently move the boarding deadline.
- Gate updates are notifications, not passenger-selected flight statuses. Keep the complete gate identifier (including `108A`) consistent across ticket, alert, map, and guidance. Back returns to the originating page; camera always has a direct exit; map/camera preserve route progress; the final route step has an End action. Onboarding runs once with an explicit replay option.

### Design and evidence

- Binding visual baseline: preserve the original overall AirBorder phone template observed before the November 7 edits, not merely its colour tokens. Keep its yellow gate signs, navy ticket, Outfit typography, card hierarchy, spacing, rounded controls and Flight/Layover/Route/Profile navigation. The target is iPhone 13 (390 × 844 logical viewport); larger browser windows must not introduce a redesigned desktop dashboard. Compare affected screens with the original Figma reference before accepting changes. Do not reinterpret the design, replace genuine Haneda imagery, or silently approve new screenshot baselines. Functional fixes must fit the original design.
- Preserve the approved AirBorder navy/blue/yellow semantic palette, Outfit typography, and genuine Haneda image provenance. Do not replace airport images with unrelated stock imagery, clip gate suffixes, invent live AR/location accuracy, or expose internal implementation language in passenger UI. Check narrow screens, visible focus, labeled controls, adequate touch targets, and readable contrast. See `Documentation/HCI/` for acceptance criteria and coverage limitations.
- Do not call a feature complete solely because a mock or fixture passes. Keep synthetic and live sources accurately described in Help/About and relevant data details. The user explicitly removed the persistent “Demo journey” note on November 7; do not reintroduce that banner or reserve screen space for it. This does not authorize describing simulated data as live. Health-derived walking estimates require consent and revocation fallback; airport-specific history and average estimates must retain provenance. LLM text cannot override deterministic timing, eligibility, or provider evidence.

### Merge evidence and boundaries

- UI review checks (`.github/workflows/ui-review.yml`): **UI copy and frozen web** blocks new iOS copy tagged “Optional”, “if needed” or “if required” and changes to the frozen `Web/` app without the owner's `web-change-approved` label. **UI review gate** requires `Preview (approved):` and `Screenshots:` links in the PR description when iOS screens, components, assets or styles change, unless labeled `no-visual-change`. Failed iOS CI or UI review runs on PRs are queued on the **UI review queue** issue; handle them with `.github/ui-review/INSTRUCTIONS.md` (image-first preview and user approval before any visual fix).
- Preserve native iOS build/unit/UI tests, backend contract/authentication tests, and browser integration/design checks. Never skip, delete, loosen assertions, blindly regenerate screenshots, or remove required checks to turn a failed PR green. Changes to workflows, tests, baselines, or these rules need explicit rationale and independent reviewer scrutiny.
- Review the affected completed flows as well as the diff. Report uncovered requirements and residual risks honestly. Do not claim a clean review guarantees a bug-free app. Provider secrets remain server-side, protected endpoints retain authentication, and public endpoints accept only bounded non-sensitive inputs.

### Passenger-facing realism

- Use natural, production-style passenger copy and retain the approved phone design. Do not label ordinary trip cards or workflows as examples or prototypes. Seeded data provenance must remain accurate and discoverable in Help/About or data details; never present simulated facts as live or connected data. Show health integration availability and consent truthfully, keep one automatically managed walking estimate with an average fallback, and do not invent demographic formulas or connection status.

- For every passenger-facing UI change, assign the `ui_researcher` role a realism pass before acceptance. Reuse the dedicated reviewer when available; preserve this check across handoffs rather than requiring the user to repeat it. The pass checks natural copy, realistic states, design preservation, and truthful availability without prototype commentary in ordinary flows.

## Report and rubric rules

`Report/main.tex` is the course deliverable (ACM `acmart` `sigconf`). It is graded against
`.github/report-review/RUBRIC.md` (CAP4104/CAP5178 Implementation and Evaluation Plan).
Any task that edits `Report/` must keep the report rubric-compliant:

- Keep the required sections: Introduction, Initial Design, System, Implementation Status,
  and Evaluation Plan with Population, Hypotheses with nulls, Method and Metrics.
- Keep the body at 5–10 pages, excluding references and the appendix, in the double-column template.
- It is a **plan**: never present user-study results, and never invent participants,
  hypotheses, numbers or citations.
- Cite only the anchor papers and project materials in `.github/report-review/ANCHORS.json`
  (at most 7 conference papers). Never add a citation; ground claims on the anchors.
- Run `python3 Scripts/reporting/check_rubric.py` and `check_citations.py` after compiling (`latexmk -pdf` in `Report/`).
- Route report edits to `docs_reporter`. A change to evaluation method or hypotheses goes
  to a deep parent.

Merge gates: `.github/workflows/report-build.yml` adds two required checks on `main`.
**Compile ACM report** fails if the report doesn't compile. **Rubric compliance** fails on any
rubric ❌ or any regression vs the base branch (`check_rubric.py --strict --baseline-tex`). Unresolved review threads also block merging.
`.github/workflows/report-review-queue.yml` runs after merge and queues a report review for
Claude in Claude Code. It is advisory and makes no AI calls in CI.

## Review guidelines

- For PRs that change a passenger-facing flow, Codex also applies
  [the advisory design review](.github/ui-review/DESIGN-REVIEW.md) even when
  CI passes. Flag a tested design that could still mislead a traveler. Name
  the observed screen or source, plausible consequence, concrete revision,
  and verification. Label missing evidence and distinguish a predicted
  misunderstanding from an observed user outcome.

Report rubric and consistency review is **Claude's job, run in Claude Code** (no API keys in
CI). Merged changes are queued on the `report-review-queue` issue by
`.github/workflows/report-review-queue.yml`, and Claude handles them by following
`.github/report-review/INSTRUCTIONS.md`.

- In routine PR reviews, do **not** duplicate rubric or citation findings on `Report/`. The
  deterministic **Rubric compliance** and **Citation anchors** checks and Claude cover them.
  Review code changes as usual.
- Do not respond to comments carrying the Claude Code attribution
  (`[Claude Code](https://claude.com/claude-code)`). Those are automated status notes, not feedback.

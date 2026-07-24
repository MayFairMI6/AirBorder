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

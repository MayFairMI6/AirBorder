# Codex agent model routing

AirportXRCompanion pins a model and reasoning effort for every supported delegated role.
The configuration is project-local, so it applies when this repository is opened as a trusted
Codex project and does not change other workspaces.

| Role | Model | Reasoning | Intended work |
|---|---|---:|---|
| Root integrator | `gpt-5.6` | high | Plan, coordinate, reconcile, and accept the complete change |
| `parent_deep` | `gpt-5.6` | xhigh | Safety-critical, ambiguous, or cross-system task chain |
| `parent_balanced` | `gpt-5.6` | high | Normal implementation and multi-file task chain |
| `parent_fast` | `gpt-5.6-terra` | medium | Mechanical search, test, log, or documentation chain |
| `architect` | `gpt-5.6` | xhigh | Ambiguous architecture, algorithms, data and provider policy |
| `safety_reviewer` | `gpt-5.6` | xhigh | Entry, connection safety, privacy, security, and uncertainty |
| `default` | `gpt-5.6-terra` | medium | General bounded fallback |
| `worker` | `gpt-5.6-terra` | medium | Implement a decided change |
| `ui_researcher` | `gpt-5.6-terra` | medium | UX research and accessible interface critique |
| `explorer` | `gpt-5.6-terra` | low | Read-only searches and evidence collection |
| `test_runner` | `gpt-5.6-terra` | low | Build/test/log execution and evidence capture |
| `docs_reporter` | `gpt-5.6-terra` | low | Evidence-based documentation synchronization |

The model split is based on decision risk, not file type. Work that can change whether a
passenger is told a city visit or connection is safe always routes to a deep role. Large but
mechanical scans, test execution, and documentation reconciliation use the faster profile.

## Files

- `.codex/config.toml` pins the root default and concurrency limits.
- `.codex/agents/*.toml` defines each spawnable role.
- `AGENTS.md` instructs the root agent how to route delegated work.
- `scripts/run-codex-parent.sh` pins a new root invocation with highest-precedence CLI overrides.

Start a parent with an explicit profile:

```bash
scripts/run-codex-parent.sh deep "Audit city-visit safety and entry-rule fallback"
scripts/run-codex-parent.sh balanced "Implement the accepted transfer UI"
scripts/run-codex-parent.sh fast "Run tests and summarize failures"
```

`auto` uses conservative keyword routing and sends ambiguous tasks to `deep`. It is a launch-time
selector, not an in-session model mutation:

```bash
scripts/run-codex-parent.sh auto "Review visa cache authority and expiry behavior"
```

The built-in names `default`, `worker`, and `explorer` are intentionally overridden so an
implicit built-in spawn still receives an explicit cost profile. Custom roles must be requested
by name. For example: `Use architect to assess the transfer model, then use worker to implement
the accepted design and test_runner to verify it.`

## Enforcement boundary

These files pin the requested settings for Codex-created sessions, but they cannot override
workspace model availability, administrator policy, or a live runtime override. Codex reapplies
the parent turn's live permission overrides to children. An unavailable pinned model should fail
visibly instead of being replaced silently; this repository explicitly requires that behavior in
`AGENTS.md`.

The parent must be selected when the session is launched or when a named parent agent is spawned.
Codex configuration does not retroactively replace the model of an open parent thread. CLI
`-c` overrides are used by the launcher because they outrank project, profile, and user config.

`Luna` is not used because it is not a model identifier documented by the current Codex manual.
If “Luna” refers to a third-party provider or a private deployment, its exact provider and model
slug must be configured before it can be evaluated or safely pinned.

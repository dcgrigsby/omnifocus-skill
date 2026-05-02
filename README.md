# omnifocus-skill

A portable skill that gives Claude (or any skill-aware agent) read/write
access to OmniFocus on macOS by composing JavaScript queries (Omni
Automation) and piping them directly to `osascript`. No server, no daemon,
no network surface.

## Status

Work in progress. Design specification:
[`docs/specs/2026-05-02-omnifocus-skill-design.md`](docs/specs/2026-05-02-omnifocus-skill-design.md).

Implementation files (`SKILL.md`, `scripts/eval.sh`, `docs/omnifocus-api/*`)
are not yet present in this repo.

## ⛔ DANGER — READ BEFORE USE

> **By installing or using this skill, you give an AI agent full read/write
> access to your OmniFocus database. Deletes are irreversible. Read
> [NOTICE](NOTICE) before proceeding.**

Specifically:

- The skill executes arbitrary JavaScript against OmniFocus with full
  privileges via `osascript`.
- There is no sandboxing and no per-call confirmation. Destructive-action
  guardrails are skill instructions, not enforced mechanisms.
- An agent that misinterprets a request, hallucinates a query, or follows a
  prompt-injection payload can permanently delete or corrupt your tasks,
  projects, and history.
- **Back up your OmniFocus database before use.**

The authors accept no liability. See [LICENSE](LICENSE) and [NOTICE](NOTICE)
for full terms.

## License

Apache 2.0 — see [LICENSE](LICENSE).

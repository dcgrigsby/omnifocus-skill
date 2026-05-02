# OmniFocus Skill — Design

**Date:** 2026-05-02
**Status:** Approved (brainstorming complete; ready for implementation planning)
**Slug:** `omnifocus`
**Repo (intended):** `github.com/dcgrigsby/omnifocus-skill`
**Install:** `npx skills add dcgrigsby/omnifocus-skill`

---

## Overview

A portable, harness-agnostic skill that gives Claude (or any skill-aware
agent) read/write access to the user's OmniFocus database on macOS. The skill
bundles the Omni Automation API reference, query/write patterns, and a small
shell wrapper that pipes JavaScript directly to `osascript`. No server, no
daemon, no network surface.

Replaces the prior NanoClaw + `omnifocal-server` architecture
(`~/omnifocal/`), collapsing two components (Go HTTP daemon + NanoClaw skill)
into one self-contained skill folder.

## Goals

- Read and write OmniFocus on the user's local machine via direct
  `osascript -l JavaScript` invocation.
- Work in any harness with skill support (Claude Code, plus others as the
  ecosystem develops).
- Trigger reliably on the right user phrasings — covering current work, past
  completions, retrospective review, decision support, planning,
  stale-review surfacing, capture, and modification.
- Stay generic and forkable. Personal workflow conventions (defer-first
  capture, tag patterns, review nudges) live in a separate
  `personal-workflow` skill, not here.

## Non-goals

- Network exposure / multi-host access (the prior architecture's job).
- Daemon / persistent process management.
- Sandboxing, authentication, or per-call write protection (the wrapper
  passes JS straight to `osascript`).
- Automated tests bundled with the skill (manual verification only).
- User-specific workflow conventions (separate skill).

## Architecture

### Directory layout

```
omnifocus-skill/
├── SKILL.md                    # frontmatter: name: omnifocus
├── README.md                   # GitHub-facing: install, safety, examples
├── LICENSE                     # Apache 2.0 (carried over from omnifocal)
├── NOTICE                      # safety warning (adapted from omnifocal)
├── scripts/
│   └── eval.sh                 # wrapper: stdin or file arg → osascript
└── docs/
    ├── specs/
    │   └── 2026-05-02-omnifocus-skill-design.md  # this document
    └── omnifocus-api/
        ├── CHEATSHEET.md       # progressive-disclosure entry point
        ├── Task.md
        ├── Project.md
        ├── Folder.md
        ├── Tag.md
        ├── Perspective.md
        ├── Forecast.md
        ├── Database.md
        ├── DateAndTime.md
        └── FULL-REFERENCE.md   # 2293-line full Omni Automation API
```

### Data flow per query

1. User asks something matching a trigger phrase (tasks, projects,
   inbox, etc.).
2. Harness loads `SKILL.md` and `docs/omnifocus-api/CHEATSHEET.md`
   (cheatsheet always; class files only when needed; `FULL-REFERENCE.md`
   only on niche surfaces explicitly named in the API Reference section).
3. Claude composes a JS query ending in `JSON.stringify(...)`.
4. Claude invokes `scripts/eval.sh` via heredoc (default) or with a file
   path (when iterating).
5. Wrapper checks OmniFocus is running. If not, exits non-zero with a clear
   stderr message; Claude surfaces this to the user (does not auto-launch).
6. Wrapper pipes the JS to `osascript -l JavaScript`. Stdout = query result
   (typically a JSON string). Stderr = any osascript error.
7. Claude parses the JSON and responds.

## Wrapper script (`scripts/eval.sh`)

### Interface

```
scripts/eval.sh                 # reads JS from stdin
scripts/eval.sh path/to/q.js    # reads JS from file
scripts/eval.sh too many args   # usage error, exits 2
```

Default invocation pattern (heredoc with quoted delimiter):

```bash
scripts/eval.sh <<'EOF'
JSON.stringify(inbox.map(t => ({ name: t.name, id: t.id.primaryKey })))
EOF
```

File-mode invocation (for queries worth keeping or iterating on):

```bash
scripts/eval.sh /tmp/of-query.js
```

The quoted delimiter (`<<'EOF'`) is required: it prevents shell expansion of
`$`, backticks, and other metacharacters inside the JS source.

### Behavior, in order

1. **Resolve source.**
   - 0 args: `src=$(cat)` from stdin.
   - 1 arg: verify the file exists; if not, print `eval.sh: file not found: <path>` to stderr, exit 2. Otherwise `src=$(cat "$1")`.
   - 2+ args: print usage to stderr, exit 2.
2. **Check OmniFocus is running.** `pgrep -x OmniFocus`. If not running,
   print `eval.sh: OmniFocus is not running. Launch it and retry.` to
   stderr, exit 3.
3. **Pipe to osascript.** `osascript -l JavaScript <<<"$src"`.
   - Stdout: osascript's stdout (the JSON result of the query).
   - Stderr: osascript's stderr (untouched).
   - Exit code: osascript's exit code.

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 2 | Usage error (bad args, file not found) |
| 3 | OmniFocus not running |
| other | osascript error (passed through) |

### Script hygiene

- Shebang: `#!/usr/bin/env bash`
- `set -euo pipefail`
- Wrapper messages prefixed `eval.sh:` and routed to stderr so they never
  pollute the JSON on stdout.
- No JSON wrapping, no retries, no timeouts, no logging, no config.

### What the skill instructions tell Claude

- On exit code 3: surface the message to the user — do not attempt to launch
  OmniFocus or work around it.
- On other non-zero: read stderr to diagnose (likely a JS error).
- For one-shot queries: use heredoc (default). For queries you want to keep
  around or iterate on: write to a temp/scratch file and invoke with the
  file argument.

## SKILL.md

### Frontmatter

```yaml
---
name: omnifocus
description: Read, write, and review the user's OmniFocus task database on
  macOS. Use whenever the user asks about: what they need to do (today's
  agenda, overdue, flagged, inbox, by project/tag), what they've already
  completed ("did I do X", "have I logged Y", "when did I finish Z"),
  retrospective review over a time window ("what did I get done this week",
  weekly/monthly review, recent activity), decision support ("what should I
  work on next", "I have an hour, what's important"), planning ("help me
  break this down into tasks", "set up a project for X"), stale or needs-
  review surfacing ("what hasn't moved in a while", "what's due for
  review"), or when capturing/modifying tasks (add to inbox, complete,
  defer, reschedule, retag). The user keeps task/project/commitment data in
  OmniFocus and reference notes/knowledge in Obsidian — anything
  representing committed or completed work belongs here.
---
```

### Body sections (in order)

1. **Title and one-paragraph overview** — what the skill does, the wrapper-
   based execution model, no server.

2. **`## When to use this skill`** — eight trigger categories, each with
   concrete user phrasings:
   - Forward-looking — what's on my plate
   - Backward-looking — what have I done
   - Retrospective review — time window
   - Decision support — what should I do next
   - Planning — break this down into tasks
   - Stale / needs review
   - Capture — new work
   - Modify — existing items

3. **`## When NOT to use this skill`** — reference material, notes,
   journaling, knowledge capture, free-form writing belong in Obsidian (or
   similar), not here. Calendar events belong in a calendar tool. Ambiguous
   capture ("track this idea" without a commitment attached) → ask the user
   which system.

4. **`## How to invoke`** — the two patterns (heredoc and file argument),
   when to use each, exit code interpretation.

5. **`## Write operations`** — confirm destructive actions (deletes, bulk
   modifications) before executing. Property-write syntax (`task.name = "x"`)
   vs. property-read syntax (`task.name`). `doc.save()` after batch
   modifications.

6. **`## Available write operations`** — per-class write-field tables,
   carried over from the old skill verbatim:
   - **Task:** `name`, `note`, `dueDate`, `deferDate`, `flagged`,
     `estimatedMinutes`, `sequential`, `completionDate`; methods
     `markComplete()`, `markIncomplete()`, `drop(flag)`, `addTag(tag)`,
     `removeTag(tag)`, `clearTags()`, `appendStringToNote(string)`;
     constructor `new Task(name, position)`.
   - **Project:** same fields plus `status`; constructor `new Project(name)`
     or `new Project(name, folder)`.
   - **Folder:** `name`, `status`; constructor `new Folder(name)` or
     `new Folder(name, parentFolder)`.
   - **Tag:** `name`, `status`; constructor `new Tag(name)` or
     `new Tag(name, parentTag)`.

7. **`## Writing queries`** — query template, global accessors table
   (inbox, flattenedTasks, flattenedProjects, flattenedFolders,
   flattenedTags, library, projects, folders, tags), lookup-by-name table
   (projectNamed, folderNamed, tagNamed, taskNamed), search table
   (projectsMatching, foldersMatching, tagsMatching).

8. **`## API reference`** — instruct Claude to read CHEATSHEET first, load
   class-specific files only when needed, and consult `FULL-REFERENCE.md`
   only for surfaces beyond the 8 focused files (Form, Alert, Selection,
   Window, Pasteboard, Settings, URL, File, Color, Image, Timer, Speech,
   Device, Crypto, Email).

9. **`## Query patterns — concrete examples`** — all 16 examples from the
   old skill rewritten to use `scripts/eval.sh <<'EOF' ... EOF`, plus one
   new example for retrospective review:
   - List inbox tasks
   - List all projects
   - Find tasks by tag
   - Search for tasks by name
   - Find overdue tasks
   - Find flagged tasks
   - List tasks in a specific project
   - List all tags
   - List all folders
   - Get tasks due soon
   - Create a new task in inbox
   - Create a task in a specific project
   - Mark a task complete
   - Set due date on a task
   - Add a tag to a task
   - Create a new project
   - **NEW:** Completed tasks in a date range (for retrospective review:
     `flattenedTasks.filter(t => t.completed && t.completionDate >= start && t.completionDate < end)`)

10. **`## Tips`** — limit results with `.slice(0, N)`, null-check before
    method calls on potentially-null fields, `.toISOString()` for date
    serialization, read stderr to diagnose query failures.

## API reference bundling

All 9 reference files copied verbatim from `~/omnifocal/docs/omnifocus-api/`
plus `~/omnifocal/docs/specs/OMNIFOCUS-OMNI-AUTOMATION-API.md` renamed to
`docs/omnifocus-api/FULL-REFERENCE.md`:

- `CHEATSHEET.md` — always loaded first
- `Task.md`, `Project.md`, `Folder.md`, `Tag.md`, `Perspective.md`,
  `Forecast.md`, `Database.md`, `DateAndTime.md` — loaded on demand
- `FULL-REFERENCE.md` — only for niche surfaces named in SKILL.md's API
  Reference section

Progressive disclosure: the cheatsheet is small and broad; class files are
focused and loaded only when a specific class is in play; the full
reference is loaded only when the cheatsheet and class files don't cover
the surface area.

## Repo-level files

### README.md

GitHub-facing. Sections:

- **What it does** — one paragraph.
- **Requirements** — macOS, OmniFocus 3 or 4, command-line tools.
- **Install** — `npx skills add dcgrigsby/omnifocus-skill`.
- **First-run note** — one sentence: "macOS will prompt once for automation
  permission to control OmniFocus."
- **Basic usage** — one heredoc example.
- **Safety** — short, link to `NOTICE`.
- **License** — Apache 2.0, link to `LICENSE`.

### LICENSE

Apache 2.0, carried over from `~/omnifocal/LICENSE` verbatim.

### NOTICE

Adapted from `~/omnifocal/NOTICE`. Drop the network-exposure language
(no server). Keep:
- The skill executes arbitrary JavaScript with full read/write privileges
  to the OmniFocus database.
- Deletes and bulk modifications are irreversible.
- Back up the OmniFocus database before use.
- The authors accept no liability.

## Coverage vs. the old skill (`~/omnifocal/skills/omnifocal/SKILL.md`)

### Carried over 1:1

- Query template (`<logic>; JSON.stringify(<result>)`).
- Property read vs. write syntax.
- All write methods and constructors per class.
- All 8 global accessors.
- Lookup-by-name and search APIs.
- `doc.save()` guidance.
- Confirm-destructive-actions guidance.
- All 8 focused API reference files.
- All 16 query-pattern examples (rewritten for `eval.sh`).
- Tips: result limiting, null checks, date formatting, error handling.

### Replaced (transport changes)

| Old | New |
|---|---|
| `POST /eval` HTTP endpoint | `scripts/eval.sh` stdin/file invocation |
| `GET /health` HTTP endpoint | (removed; OmniFocus running check is in wrapper) |
| HTTP 200 / 400 / 500 | Exit codes 0 / 2 / 3 / other |
| launchd daemon, `--i-accept-the-risk` flag | (removed; no server) |
| Network-exposure warnings in NOTICE | (dropped; no network surface) |

### Added

- `## When to use` with 8 trigger categories and concrete phrasings.
- `## When NOT to use` with the Obsidian/notes boundary.
- "Completed tasks in date range" query example for retrospective review.
- File-argument invocation pattern alongside heredoc.
- `FULL-REFERENCE.md` bundled with progressive-disclosure pointer.

### Dropped (intentional)

- HTTP server (omnifocal-server Go binary).
- launchd integration.
- /health endpoint.
- Read-only-by-instruction constraint (the old skill itself had already
  moved to read/write; carried forward).
- NanoClaw container networking guidance.

## Out of scope (separate skill)

The user's personal workflow conventions are deliberately **not** in this
skill. They live in a future `personal-workflow` skill (handoff doc:
`/Users/dan/personal-workflow-handoff.md`):

- Defer-first capture (no due dates by default; "by X" → defer until X).
- Tags-as-people-plus-1:1.
- No use of flags.
- Defer time-of-day defaults to 00:00.
- Proactive review nudges.
- Proactive capture nudges for incidental commitments.

These conventions are *opinions* about how to use OmniFocus, not
*capabilities* of OmniFocus. Keeping them out of this skill makes the
skill generic, forkable, and reusable. The `personal-workflow` skill
layers on top with the user's preferences and handles cross-tool routing
(OmniFocus vs. Obsidian).

## Testing approach

Manual only. No automated test scaffolding ships with the skill.
Verification:

1. Install the skill in Claude Code.
2. Ask Claude to run a few read queries: "what's in my inbox?", "show me
   overdue tasks", "what did I complete this week?".
3. Ask Claude to run one safe write: "add a test task to my inbox called
   'skill verification'".
4. Confirm the wrapper handles the OmniFocus-not-running case: quit
   OmniFocus, retry a query, confirm exit code 3 and clear error.
5. Confirm the wrapper handles a malformed query: pass invalid JS, confirm
   the osascript error is surfaced on stderr with non-zero exit.

The old project's Kilroy-based pipeline testing is overkill for a
single-file capability skill.

## Open implementation questions

None. All design decisions resolved during brainstorming.

## Implementation order (for the writing-plans phase)

1. Create the skill repo skeleton (directories, README, LICENSE, NOTICE).
2. Write `scripts/eval.sh` and verify it manually with a one-line query.
3. Copy the 8 focused API reference files and `FULL-REFERENCE.md` from
   `~/omnifocal/docs/`.
4. Write `SKILL.md` (frontmatter, all 10 body sections).
5. Manual verification with the test scenarios above.
6. Initialize git, commit, push to `github.com/dcgrigsby/omnifocus-skill`.
7. Test installation: `npx skills add dcgrigsby/omnifocus-skill` in a
   fresh Claude Code project, run the verification scenarios.

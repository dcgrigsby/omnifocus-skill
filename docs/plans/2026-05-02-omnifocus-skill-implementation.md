# OmniFocus Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the `omnifocus` capability skill per the approved spec, ship to the existing public GitHub repo `dcgrigsby/omnifocus-skill`, and verify install via `npx skills add`.

**Architecture:** A portable skill folder. macOS-only osascript wrapper at `scripts/eval.sh` reads JS from stdin or a file argument and pipes to `osascript -l JavaScript`. `SKILL.md` at repo root teaches Claude when to invoke and how to compose queries. Reference docs at `docs/omnifocus-api/*.md` use progressive disclosure (cheatsheet first, class files on demand, full reference for niche surfaces).

**Tech Stack:** Bash (`#!/usr/bin/env bash`, `set -euo pipefail`), `osascript -l JavaScript` (Omni Automation), Markdown.

**Spec reference:** [`docs/specs/2026-05-02-omnifocus-skill-design.md`](../specs/2026-05-02-omnifocus-skill-design.md)

**Pre-existing state:** The repo is initialized and pushed to `github.com/dcgrigsby/omnifocus-skill` (initial commit `e3dd35e` contains LICENSE, NOTICE, README.md, the design spec, and this plan once committed). All work continues on `main`.

---

## File Structure

| Path | Purpose |
|---|---|
| `scripts/eval.sh` | Wrapper: stdin or file arg → `osascript -l JavaScript` |
| `docs/omnifocus-api/CHEATSHEET.md` | Always-loaded API overview |
| `docs/omnifocus-api/Task.md` | Class reference, on-demand |
| `docs/omnifocus-api/Project.md` | Class reference, on-demand |
| `docs/omnifocus-api/Folder.md` | Class reference, on-demand |
| `docs/omnifocus-api/Tag.md` | Class reference, on-demand |
| `docs/omnifocus-api/Perspective.md` | Class reference, on-demand |
| `docs/omnifocus-api/Forecast.md` | Class reference, on-demand |
| `docs/omnifocus-api/Database.md` | Class reference, on-demand |
| `docs/omnifocus-api/DateAndTime.md` | Class reference, on-demand |
| `docs/omnifocus-api/FULL-REFERENCE.md` | Niche-surface reference (Form, Alert, Selection, Window, Pasteboard, Settings, etc.) |
| `SKILL.md` | Skill instruction file with frontmatter and 10 body sections |

Source files for the API reference docs are in `~/omnifocal/docs/omnifocus-api/` (8 files) and `~/omnifocal/docs/specs/OMNIFOCUS-OMNI-AUTOMATION-API.md` (renamed to `FULL-REFERENCE.md`).

---

## Task 1: Wrapper script (`scripts/eval.sh`)

**Files:**
- Create: `/Users/dan/omnifocus-skill/scripts/eval.sh`

- [ ] **Step 1: Create the scripts directory and write `eval.sh`**

```bash
mkdir -p /Users/dan/omnifocus-skill/scripts
```

**Important implementation note:** `osascript -l JavaScript` runs in JXA (JavaScript for Automation) mode, which does NOT expose the Omni Automation globals (`flattenedTasks`, `inbox`, etc.). To reach the Omni Automation API, the wrapper bridges through AppleScript's `tell application "OmniFocus" to evaluate javascript "..."`, which runs the JS inside OmniFocus's own scripting engine. This matches the approach used by the predecessor `omnifocal-server` (see `~/omnifocal/cmd/omnifocal-server/main.go`).

Write `/Users/dan/omnifocus-skill/scripts/eval.sh` with this exact content:

```bash
#!/usr/bin/env bash
# eval.sh — pipe JavaScript (Omni Automation) to OmniFocus via osascript.
#
# Usage:
#   scripts/eval.sh                  # read JS from stdin
#   scripts/eval.sh path/to/query.js # read JS from file
#
# Exit codes:
#   0       success
#   2       usage error (bad args, file not found)
#   3       OmniFocus is not running
#   other   osascript / Omni Automation error (passed through)
#
# Implementation note: osascript's -l JavaScript mode is JXA, which does NOT
# expose Omni Automation globals (flattenedTasks, inbox, etc.). To reach the
# Omni Automation API we bridge through AppleScript's `evaluate javascript`,
# which runs the JS inside OmniFocus's own scripting engine.

set -euo pipefail

# Resolve source: stdin or single positional file arg.
if [[ $# -eq 0 ]]; then
  src=$(cat)
elif [[ $# -eq 1 ]]; then
  if [[ ! -f "$1" ]]; then
    echo "eval.sh: file not found: $1" >&2
    exit 2
  fi
  src=$(cat "$1")
else
  echo "eval.sh: too many arguments. Usage: eval.sh [file.js] (or pipe JS via stdin)" >&2
  exit 2
fi

# Verify OmniFocus is running. Do not auto-launch.
if ! pgrep -x OmniFocus >/dev/null 2>&1; then
  echo "eval.sh: OmniFocus is not running. Launch it and retry." >&2
  exit 3
fi

# Escape JS for embedding in an AppleScript string literal.
# Order matters: backslashes first, then double quotes, then newlines.
escaped=${src//\\/\\\\}
escaped=${escaped//\"/\\\"}
escaped=${escaped//$'\n'/\\n}

# Bridge to Omni Automation via AppleScript's `evaluate javascript`.
exec osascript -e "tell application \"OmniFocus\" to evaluate javascript \"$escaped\""
```

- [ ] **Step 2: Make the script executable**

Run:
```bash
chmod +x /Users/dan/omnifocus-skill/scripts/eval.sh
```

Verify:
```bash
ls -l /Users/dan/omnifocus-skill/scripts/eval.sh
```

Expected: mode `-rwxr-xr-x`.

- [ ] **Step 3: Smoke-test against a running OmniFocus**

Confirm OmniFocus is running (`pgrep -x OmniFocus` returns a PID), then:

```bash
/Users/dan/omnifocus-skill/scripts/eval.sh <<'EOF'
JSON.stringify({ taskCount: flattenedTasks.length })
EOF
```

Expected: stdout is a single line of JSON like `{"taskCount":1234}`. Exit code 0.

If macOS prompts for automation permission ("Terminal/iTerm wants to control OmniFocus"), grant it. This is a one-time prompt.

- [ ] **Step 4: Test usage error — too many arguments**

```bash
/Users/dan/omnifocus-skill/scripts/eval.sh foo bar
echo "exit=$?"
```

Expected stderr: `eval.sh: too many arguments. Usage: eval.sh [file.js] (or pipe JS via stdin)`
Expected: `exit=2`

- [ ] **Step 5: Test usage error — file not found**

```bash
/Users/dan/omnifocus-skill/scripts/eval.sh /tmp/does-not-exist-12345.js
echo "exit=$?"
```

Expected stderr: `eval.sh: file not found: /tmp/does-not-exist-12345.js`
Expected: `exit=2`

- [ ] **Step 6: Test file-mode invocation**

```bash
cat > /tmp/of-smoke.js <<'EOF'
JSON.stringify({ projectCount: flattenedProjects.length })
EOF
/Users/dan/omnifocus-skill/scripts/eval.sh /tmp/of-smoke.js
echo "exit=$?"
rm /tmp/of-smoke.js
```

Expected stdout: a single line of JSON like `{"projectCount":42}`.
Expected: `exit=0`.

- [ ] **Step 7: Test osascript error pass-through**

```bash
/Users/dan/omnifocus-skill/scripts/eval.sh <<'EOF'
this_is_not_valid_javascript ++ ;;
EOF
echo "exit=$?"
```

Expected: stderr contains osascript's syntax-error message; exit code is non-zero (typically 1).

**Note (deferred):** Exit code 3 (OmniFocus not running) cannot be verified without quitting OmniFocus, which is destructive to your active work. Defer this verification until OmniFocus happens to be quit (e.g., after a system restart). To test then:

```bash
osascript -e 'tell application "OmniFocus" to quit'
sleep 2
/Users/dan/omnifocus-skill/scripts/eval.sh <<<'JSON.stringify(1)'
echo "exit=$?"
# Expected stderr: "eval.sh: OmniFocus is not running. Launch it and retry."
# Expected: exit=3
```

- [ ] **Step 8: Commit**

```bash
git -C /Users/dan/omnifocus-skill add scripts/eval.sh
git -C /Users/dan/omnifocus-skill commit -m "$(cat <<'EOF'
Add eval.sh wrapper for osascript invocation

Reads JavaScript from stdin (default) or a file argument and pipes it to
`osascript -l JavaScript` against OmniFocus. Fails fast with exit code 3 if
OmniFocus is not running — no auto-launch. Stderr carries wrapper messages
and osascript errors; stdout carries the JSON result.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: API reference docs

**Files:**
- Create: `/Users/dan/omnifocus-skill/docs/omnifocus-api/{CHEATSHEET,Task,Project,Folder,Tag,Perspective,Forecast,Database,DateAndTime,FULL-REFERENCE}.md`

**Source:** Existing files in `~/omnifocal/docs/omnifocus-api/` (8 focused files) and `~/omnifocal/docs/specs/OMNIFOCUS-OMNI-AUTOMATION-API.md` (the full reference, renamed during copy).

- [ ] **Step 1: Create the destination directory and copy the 8 focused files**

```bash
mkdir -p /Users/dan/omnifocus-skill/docs/omnifocus-api
cp ~/omnifocal/docs/omnifocus-api/CHEATSHEET.md /Users/dan/omnifocus-skill/docs/omnifocus-api/
cp ~/omnifocal/docs/omnifocus-api/Task.md /Users/dan/omnifocus-skill/docs/omnifocus-api/
cp ~/omnifocal/docs/omnifocus-api/Project.md /Users/dan/omnifocus-skill/docs/omnifocus-api/
cp ~/omnifocal/docs/omnifocus-api/Folder.md /Users/dan/omnifocus-skill/docs/omnifocus-api/
cp ~/omnifocal/docs/omnifocus-api/Tag.md /Users/dan/omnifocus-skill/docs/omnifocus-api/
cp ~/omnifocal/docs/omnifocus-api/Perspective.md /Users/dan/omnifocus-skill/docs/omnifocus-api/
cp ~/omnifocal/docs/omnifocus-api/Forecast.md /Users/dan/omnifocus-skill/docs/omnifocus-api/
cp ~/omnifocal/docs/omnifocus-api/Database.md /Users/dan/omnifocus-skill/docs/omnifocus-api/
cp ~/omnifocal/docs/omnifocus-api/DateAndTime.md /Users/dan/omnifocus-skill/docs/omnifocus-api/
```

- [ ] **Step 2: Copy the full reference and rename**

```bash
cp ~/omnifocal/docs/specs/OMNIFOCUS-OMNI-AUTOMATION-API.md /Users/dan/omnifocus-skill/docs/omnifocus-api/FULL-REFERENCE.md
```

- [ ] **Step 3: Verify all 10 files are present**

```bash
ls -1 /Users/dan/omnifocus-skill/docs/omnifocus-api/
```

Expected output (alphabetical):
```
CHEATSHEET.md
DateAndTime.md
Database.md
Folder.md
Forecast.md
FULL-REFERENCE.md
Perspective.md
Project.md
Tag.md
Task.md
```

(That's 10 files.)

- [ ] **Step 4: Spot-check `FULL-REFERENCE.md` opens correctly**

```bash
head -5 /Users/dan/omnifocus-skill/docs/omnifocus-api/FULL-REFERENCE.md
```

Expected: starts with `# OmniFocus Omni Automation JavaScript API Reference`.

- [ ] **Step 5: Commit**

```bash
git -C /Users/dan/omnifocus-skill add docs/omnifocus-api/
git -C /Users/dan/omnifocus-skill commit -m "$(cat <<'EOF'
Add Omni Automation API reference (10 files, progressive disclosure)

Bundles 9 focused class files (CHEATSHEET, Task, Project, Folder, Tag,
Perspective, Forecast, Database, DateAndTime) plus FULL-REFERENCE.md
(the complete extracted Omni Automation API for niche surfaces like
Form, Alert, Selection, Pasteboard, Settings, etc.).

SKILL.md will instruct readers to load CHEATSHEET first, class files on
demand, and FULL-REFERENCE only when the focused files don't cover the
surface area.

Source: ~/omnifocal/docs/omnifocus-api/ and ~/omnifocal/docs/specs/.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `SKILL.md`

**Files:**
- Create: `/Users/dan/omnifocus-skill/SKILL.md`

This is the largest deliverable. Structure: YAML frontmatter, then 10 body sections in the order specified by the spec.

The "Available write operations," "Writing queries" tables, "Tips," and 16 of the 17 query-pattern examples are carried over from the old skill at `~/omnifocal/skills/omnifocal/SKILL.md` — but with every `curl -s -X POST -d '...' http://localhost:7890/eval` invocation rewritten to `scripts/eval.sh <<'EOF' ... EOF`.

- [ ] **Step 1: Write the complete `SKILL.md`**

Write `/Users/dan/omnifocus-skill/SKILL.md` with this exact content:

```markdown
---
name: omnifocus
description: Read, write, and review the user's OmniFocus task database on macOS. Use whenever the user asks about what they need to do (today's agenda, overdue, flagged, inbox, by project/tag), what they've already completed ("did I do X", "have I logged Y", "when did I finish Z"), retrospective review over a time window ("what did I get done this week", weekly/monthly review, recent activity), decision support ("what should I work on next", "I have an hour, what's important"), planning ("help me break this down into tasks", "set up a project for X"), stale or needs-review surfacing ("what hasn't moved in a while", "what's due for review"), or when capturing/modifying tasks (add to inbox, complete, defer, reschedule, retag). The user keeps task/project/commitment data in OmniFocus and reference notes/knowledge in Obsidian — anything representing committed or completed work belongs here.
---

# OmniFocus

This skill lets you read and write OmniFocus data on the user's Mac by composing JavaScript (Omni Automation) and piping it through the bundled `scripts/eval.sh` wrapper to `osascript`. No server, no daemon, no network surface — direct local execution.

## When to use this skill

Use this skill any time the user is asking about, working with, or capturing **task and project data** from their OmniFocus database. Common categories with example phrasings:

**1. Forward-looking — what's on my plate**
- "What do I have to do today / this week?"
- "What's overdue?"
- "What's flagged?"
- "What's in my inbox?"
- "Show me everything in `<project>`"
- "What do I have for `<tag>`?"
- "Anything blocked / waiting?"

**2. Backward-looking — what have I done**
- "Did I finish the X report?"
- "Have I logged the Y task?"
- "When did I complete Z?"
- "Show me what I marked done in the `<project>` project"

**3. Retrospective review — time window**
- "What did I get done this week / last week / this month / Q1?"
- "Generate a weekly review"
- "What was I working on around `<date>`?"
- "Activity over the last N days"

**4. Decision support — what should I do next**
- "What should I work on?"
- "I have an hour — what's important?"
- "Help me pick something to do"
- "What's the most important thing right now?"

(Don't dump a raw list when the user asked for a recommendation. Fetch the relevant tasks, then reason and recommend.)

**5. Planning — break this down into tasks**
- "Help me break this down into tasks"
- "Set up a project for `<topic>`"
- "I'm planning a `<move/launch/trip>` — build the project structure"

(Design the work first, then create the tasks. Don't dump a single line into the inbox when the user asked for a project.)

**6. Stale / needs review**
- "What needs review?"
- "What's been sitting?"
- "Stale projects"
- "What haven't I touched in a while?"

(Use OmniFocus's first-class `nextReviewDate` and `lastReviewDate` properties — don't fabricate staleness from other signals when the real fields exist.)

**7. Capture — new work**
- "Add a task to my inbox: ..."
- "Create a project for `<topic>`"
- "Add `<X>` to the `<project>` project"
- "Remind me to ... by Thursday"

**8. Modify — existing items**
- Complete, uncomplete, defer, reschedule, retag, move, flag, unflag
- Edit notes, change estimates, mark sequential/parallel
- Move tasks between projects or folders

## When NOT to use this skill

The user keeps **reference material, notes, knowledge, journaling, and free-form writing** in Obsidian, not OmniFocus. Don't reach for this skill when the user says things like "write a note about...", "log my thoughts on...", "draft a doc...", or "save this for reference." Those belong in a notes tool.

Don't use this skill for **calendar events** (use a calendar tool) or for **email** (use an email tool).

If the request is ambiguous — "track this idea" or "save this for later" without a clear commitment attached — ask which system the user wants it in.

## How to invoke

Two patterns. Pick the right one for the situation.

### Heredoc (default — for queries you compose on the fly)

```bash
scripts/eval.sh <<'EOF'
JSON.stringify(inbox.map(t => ({ name: t.name, id: t.id.primaryKey })))
EOF
```

The quoted delimiter `<<'EOF'` is required — it prevents shell expansion of `$`, backticks, and other metacharacters inside the JS source. Use this pattern for one-shot queries.

### File argument (for queries worth keeping or iterating on)

```bash
# Write the query to a temp file
cat > /tmp/of-query.js <<'EOF'
var p = projectNamed("Q2 Planning");
JSON.stringify(p ? p.flattenedTasks.map(t => ({ name: t.name, status: t.taskStatus.name })) : null)
EOF

# Execute
scripts/eval.sh /tmp/of-query.js
```

Use this when:
- You're iterating on a complex query and want to re-run it
- You're debugging something and want the JS preserved as a reviewable artifact
- The query is long enough that having it in a file aids review

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success — JSON result on stdout |
| 2 | Usage error (bad args or file not found) — see stderr |
| 3 | OmniFocus is not running. **Surface this to the user** — do not attempt to launch it. |
| other | osascript error (e.g., JS syntax error) — see stderr for details |

On any non-zero exit, read stderr to diagnose.

## Write operations

You can create, modify, and complete OmniFocus items. When performing write operations:

- **Always confirm destructive actions with the user** before deleting tasks, projects, or folders, or before bulk modifications that loop over many items.
- **Use `save()` sparingly** — OmniFocus auto-saves, but call `doc.save()` after batch modifications to ensure persistence.
- Property writes use assignment syntax: `task.name = "new name"` (not method-call syntax).
- Property reads use property access: `task.name` (not method-call syntax).

### Available write operations

**Task:** set `name`, `note`, `dueDate`, `deferDate`, `flagged`, `estimatedMinutes`, `sequential`, `completionDate`; call `markComplete()`, `markIncomplete()`, `drop(flag)`, `addTag(tag)`, `removeTag(tag)`, `clearTags()`, `appendStringToNote(string)`; create with `new Task(name, position)`.

**Project:** set `name`, `note`, `dueDate`, `deferDate`, `flagged`, `estimatedMinutes`, `sequential`, `status`, `completionDate`; call `markComplete()`, `markIncomplete()`, `addTag(tag)`, `removeTag(tag)`; create with `new Project(name)` or `new Project(name, folder)`.

**Folder:** set `name`, `status`; create with `new Folder(name)` or `new Folder(name, parentFolder)`.

**Tag:** set `name`, `status`; create with `new Tag(name)` or `new Tag(name, parentTag)`.

## Writing queries

### Query template

Every query follows this pattern:

```javascript
<your query logic>; JSON.stringify(<result>)
```

Key points:
- Global accessors are available directly: `inbox`, `flattenedTasks`, `flattenedProjects`, etc. — no `Application()` or `document` prefix needed.
- Always wrap the final result in `JSON.stringify()` so the output is parseable JSON.
- Property access uses direct dot notation: `task.name` not `task.name()`.
- Property writes use assignment: `task.name = "new name"`.
- Standard JS works: `.map()`, `.filter()`, arrow functions, template literals.

### Available global accessors

| Accessor | Returns | Description |
|---|---|---|
| `inbox` | TaskArray | Inbox tasks |
| `flattenedTasks` | TaskArray | All tasks (flattened hierarchy) |
| `flattenedProjects` | ProjectArray | All projects |
| `flattenedFolders` | FolderArray | All folders |
| `flattenedTags` | TagArray | All tags |
| `library` | SectionArray | Top-level library |
| `projects` | ProjectArray | Top-level projects |
| `folders` | FolderArray | Top-level folders |
| `tags` | Tags | Top-level tags |

### Lookup by name

| Method | Returns |
|---|---|
| `projectNamed("name")` | Project or null |
| `folderNamed("name")` | Folder or null |
| `tagNamed("name")` | Tag or null |
| `taskNamed("name")` | Task or null |

### Search (substring match)

| Method | Returns |
|---|---|
| `projectsMatching("search")` | Array of Projects |
| `foldersMatching("search")` | Array of Folders |
| `tagsMatching("search")` | Array of Tags |

## API reference

The Omni Automation API reference is split into focused files for progressive discovery:

1. **Start here:** Read `docs/omnifocus-api/CHEATSHEET.md` for a compact overview of all classes, properties, and methods.
2. **Deep dive:** For details on a specific class, read its individual reference file:
   - `docs/omnifocus-api/Task.md`
   - `docs/omnifocus-api/Project.md`
   - `docs/omnifocus-api/Folder.md`
   - `docs/omnifocus-api/Tag.md`
   - `docs/omnifocus-api/Perspective.md`
   - `docs/omnifocus-api/Forecast.md`
   - `docs/omnifocus-api/Database.md`
   - `docs/omnifocus-api/DateAndTime.md`
3. **Niche surfaces:** For surfaces beyond the focused files (Form, Alert, Selection, Window, Pasteboard, Settings, URL, File, Color, Image, Timer, Speech, Device, Crypto, Email), see `docs/omnifocus-api/FULL-REFERENCE.md`. Only load this when the focused files don't cover what you need — it's much larger.

Always read the cheatsheet first. Only load other files when you need details beyond what the cheatsheet provides.

## Query patterns — concrete examples

### List inbox tasks

```bash
scripts/eval.sh <<'EOF'
JSON.stringify(inbox.map(t => ({ name: t.name, id: t.id.primaryKey, flagged: t.flagged })))
EOF
```

### List all projects

```bash
scripts/eval.sh <<'EOF'
JSON.stringify(flattenedProjects.map(p => ({ name: p.name, status: p.status.name, id: p.id.primaryKey })))
EOF
```

### Find tasks by tag

```bash
scripts/eval.sh <<'EOF'
var tag = tagNamed("work");
JSON.stringify(tag ? tag.tasks.map(t => ({ name: t.name, id: t.id.primaryKey, due: t.dueDate ? t.dueDate.toISOString() : null })) : [])
EOF
```

### Search for tasks by name

```bash
scripts/eval.sh <<'EOF'
JSON.stringify(flattenedTasks.filter(t => t.name.toLowerCase().includes("report")).map(t => ({ name: t.name, id: t.id.primaryKey, project: t.containingProject ? t.containingProject.name : null })))
EOF
```

### Find overdue tasks

```bash
scripts/eval.sh <<'EOF'
JSON.stringify(flattenedTasks.filter(t => t.taskStatus === Task.Status.Overdue).map(t => ({ name: t.name, due: t.effectiveDueDate ? t.effectiveDueDate.toISOString() : null, project: t.containingProject ? t.containingProject.name : null })))
EOF
```

### Find flagged tasks

```bash
scripts/eval.sh <<'EOF'
JSON.stringify(flattenedTasks.filter(t => t.effectiveFlagged && !t.completed).map(t => ({ name: t.name, id: t.id.primaryKey, due: t.dueDate ? t.dueDate.toISOString() : null })))
EOF
```

### List tasks in a specific project

```bash
scripts/eval.sh <<'EOF'
var proj = projectNamed("My Project");
JSON.stringify(proj ? proj.flattenedTasks.map(t => ({ name: t.name, status: t.taskStatus.name, completed: t.completed })) : [])
EOF
```

### List all tags

```bash
scripts/eval.sh <<'EOF'
JSON.stringify(flattenedTags.map(tg => ({ name: tg.name, id: tg.id.primaryKey, taskCount: tg.tasks.length })))
EOF
```

### List all folders

```bash
scripts/eval.sh <<'EOF'
JSON.stringify(flattenedFolders.map(f => ({ name: f.name, id: f.id.primaryKey, projectCount: f.projects.length })))
EOF
```

### Get tasks due soon

```bash
scripts/eval.sh <<'EOF'
JSON.stringify(flattenedTasks.filter(t => t.taskStatus === Task.Status.DueSoon).map(t => ({ name: t.name, due: t.effectiveDueDate ? t.effectiveDueDate.toISOString() : null })))
EOF
```

### Completed tasks in a date range (retrospective review)

```bash
scripts/eval.sh <<'EOF'
var start = new Date("2026-04-25T00:00:00");
var end = new Date("2026-05-02T00:00:00");
JSON.stringify(
  flattenedTasks
    .filter(t => t.completed && t.completionDate && t.completionDate >= start && t.completionDate < end)
    .map(t => ({
      name: t.name,
      completed: t.completionDate.toISOString(),
      project: t.containingProject ? t.containingProject.name : null,
      tags: t.tags.map(tg => tg.name)
    }))
)
EOF
```

Adjust `start` and `end` for the desired window. Use this pattern for "what did I get done this week / last week / this month / since X."

### Create a new task in inbox

```bash
scripts/eval.sh <<'EOF'
var t = new Task("Buy groceries", inbox.beginning);
JSON.stringify({ name: t.name, id: t.id.primaryKey })
EOF
```

### Create a task in a specific project

```bash
scripts/eval.sh <<'EOF'
var proj = projectNamed("My Project");
var t = new Task("Write report", proj);
JSON.stringify({ name: t.name, id: t.id.primaryKey, project: t.containingProject.name })
EOF
```

### Mark a task complete

```bash
scripts/eval.sh <<'EOF'
var t = flattenedTasks.find(t => t.name === "Buy groceries");
if (t) {
  t.markComplete();
  JSON.stringify({ name: t.name, completed: t.completed });
} else {
  JSON.stringify({ error: "task not found" });
}
EOF
```

### Set due date on a task

```bash
scripts/eval.sh <<'EOF'
var t = flattenedTasks.find(t => t.name === "Write report");
if (t) {
  t.dueDate = new Date("2026-06-01T17:00:00");
  JSON.stringify({ name: t.name, due: t.dueDate.toISOString() });
} else {
  JSON.stringify({ error: "task not found" });
}
EOF
```

### Add a tag to a task

```bash
scripts/eval.sh <<'EOF'
var t = flattenedTasks.find(t => t.name === "Write report");
var tag = tagNamed("urgent");
if (t && tag) {
  t.addTag(tag);
  JSON.stringify({ name: t.name, tags: t.tags.map(tg => tg.name) });
} else {
  JSON.stringify({ error: "task or tag not found" });
}
EOF
```

### Create a new project

```bash
scripts/eval.sh <<'EOF'
var p = new Project("Q2 Planning");
JSON.stringify({ name: p.name, id: p.id.primaryKey })
EOF
```

## Tips

- **Limit results:** for large databases, use `.slice(0, N)` to limit output. Many users have thousands of tasks.
- **Check for null:** many properties can be null (`dueDate`, `deferDate`, `containingProject`, etc.). Always check before calling methods on them.
- **Date formatting:** use `.toISOString()` on `Date` objects for consistent JSON serialization.
- **Tag and project lookup:** use `tagNamed("x")` / `projectNamed("x")` for exact match (returns the object or null); use `tagsMatching("x")` / `projectsMatching("x")` for substring match (returns an array).
- **Error handling:** on non-zero exit from `scripts/eval.sh`, read stderr. Exit code 3 means OmniFocus isn't running — surface that to the user, don't try to work around it. Other non-zero codes typically mean a JS error in your query.
- **Identifying tasks reliably:** when modifying tasks, prefer matching by `id.primaryKey` if you have it. Matching by `name` can match the wrong task if names aren't unique.
```

- [ ] **Step 2: Verify the file structure**

```bash
head -3 /Users/dan/omnifocus-skill/SKILL.md
```

Expected: `---` then `name: omnifocus` then a `description: ...` line.

```bash
grep -c '^## ' /Users/dan/omnifocus-skill/SKILL.md
```

Expected: `9` (When to use, When NOT to use, How to invoke, Write operations, Writing queries, API reference, Query patterns — concrete examples, Tips, plus one for the title... wait, only `## ` is counted, not `# `. Sections: When to use, When NOT to use, How to invoke, Write operations, Writing queries, API reference, Query patterns, Tips = 8). Expected `8`.

If the count is wrong, recount the sections in the file and confirm against the spec section list.

- [ ] **Step 3: Verify the heredoc pattern is used consistently**

```bash
grep -c "scripts/eval.sh <<'EOF'" /Users/dan/omnifocus-skill/SKILL.md
```

Expected: 17 (one per query-pattern example: 16 carried over + 1 new = 17).

- [ ] **Step 4: Confirm no `curl` invocations leaked from the old skill**

```bash
grep -c 'curl' /Users/dan/omnifocus-skill/SKILL.md
```

Expected: `0`.

- [ ] **Step 5: Commit**

```bash
git -C /Users/dan/omnifocus-skill add SKILL.md
git -C /Users/dan/omnifocus-skill commit -m "$(cat <<'EOF'
Add SKILL.md with frontmatter and 8 body sections

Trigger-rich frontmatter description names eight intent categories
(forward-looking, backward-looking, retrospective review, decision
support, planning, stale/review, capture, modify) so the skill fires on
the right user phrasings.

Body sections: When to use / When NOT to use (with the OmniFocus/
Obsidian boundary), How to invoke (heredoc and file-arg patterns plus
exit-code interpretation), Write operations and per-class write tables,
Writing queries (template, accessors, lookup, search), API reference
(progressive disclosure across 9 focused files plus FULL-REFERENCE for
niche surfaces), 17 concrete query-pattern examples (16 carried over
from the predecessor skill + new "completed in date range" example for
retrospective review), and tips.

All examples invoke scripts/eval.sh via heredoc with quoted delimiter.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: End-to-end manual verification

**Files:** none (verification only).

These scenarios exercise the full skill against a running OmniFocus to confirm everything composes correctly.

- [ ] **Step 1: Verify a read query returns sensible data**

```bash
cd /Users/dan/omnifocus-skill
./scripts/eval.sh <<'EOF'
JSON.stringify({
  inbox: inbox.length,
  projects: flattenedProjects.length,
  tags: flattenedTags.length,
  tasks: flattenedTasks.length
})
EOF
```

Expected: a JSON object with four positive integer counts. Exit 0.

- [ ] **Step 2: Verify the "completed in date range" query**

```bash
cd /Users/dan/omnifocus-skill
./scripts/eval.sh <<'EOF'
var end = new Date();
var start = new Date(end.getTime() - 7 * 24 * 60 * 60 * 1000);
JSON.stringify({
  windowStart: start.toISOString(),
  windowEnd: end.toISOString(),
  count: flattenedTasks.filter(t => t.completed && t.completionDate && t.completionDate >= start && t.completionDate < end).length
})
EOF
```

Expected: a JSON object showing the last-7-days window and a count of completed tasks. Exit 0.

- [ ] **Step 3: Verify a safe write — create and immediately delete a test task**

Create:

```bash
cd /Users/dan/omnifocus-skill
./scripts/eval.sh <<'EOF'
var t = new Task("__skill verification — safe to delete__", inbox.beginning);
JSON.stringify({ name: t.name, id: t.id.primaryKey })
EOF
```

Expected stdout: `{"name":"__skill verification — safe to delete__","id":"<some id>"}`. Note the id from the output.

Verify it appears in OmniFocus (open the inbox, look for the task).

Delete it:

```bash
cd /Users/dan/omnifocus-skill
./scripts/eval.sh <<'EOF'
var t = flattenedTasks.find(t => t.name === "__skill verification — safe to delete__");
if (t) {
  deleteObject(t);
  JSON.stringify({ deleted: true });
} else {
  JSON.stringify({ error: "task not found" });
}
EOF
```

Expected stdout: `{"deleted":true}`. Verify the task is gone from OmniFocus.

- [ ] **Step 4: Verify the API reference loads**

```bash
head -10 /Users/dan/omnifocus-skill/docs/omnifocus-api/CHEATSHEET.md
```

Expected: a markdown header for the cheatsheet.

```bash
wc -l /Users/dan/omnifocus-skill/docs/omnifocus-api/FULL-REFERENCE.md
```

Expected: ~2293 lines.

- [ ] **Step 5: No commit needed** (verification only — no files changed).

---

## Task 5: Push and install test

**Files:** none (operational).

- [ ] **Step 1: Confirm working tree is clean**

```bash
git -C /Users/dan/omnifocus-skill status
```

Expected: `nothing to commit, working tree clean`.

- [ ] **Step 2: Push all commits**

```bash
git -C /Users/dan/omnifocus-skill push
```

Expected: pushes commits from Tasks 1, 2, 3 (and this plan, if committed) to `origin/main`.

- [ ] **Step 3: Verify the repo on GitHub**

Open in browser: https://github.com/dcgrigsby/omnifocus-skill

Confirm the repo shows:
- `LICENSE`, `NOTICE`, `README.md` at root
- `SKILL.md` at root
- `docs/specs/` and `docs/plans/` directories
- `docs/omnifocus-api/` directory with 10 files
- `scripts/eval.sh`

- [ ] **Step 4: Install via `npx skills add` in a fresh test directory**

```bash
mkdir -p /tmp/skill-install-test
cd /tmp/skill-install-test
npx skills add dcgrigsby/omnifocus-skill
```

Expected: command completes successfully and the skill is registered. Inspect the destination location reported by the installer.

- [ ] **Step 5: Verify the installed skill has executable wrapper**

Locate the installed skill directory (the `npx skills add` output should report it; commonly `~/.claude/skills/omnifocus/` or similar). Then:

```bash
ls -l <installed-skill-path>/scripts/eval.sh
```

Expected: file exists and is executable (`-rwxr-xr-x` or similar). If it's not executable, the installer didn't preserve permissions — note this and `chmod +x` manually as a workaround.

- [ ] **Step 6: Smoke test the installed skill**

```bash
<installed-skill-path>/scripts/eval.sh <<'EOF'
JSON.stringify(inbox.length)
EOF
```

Expected: a positive integer. Exit 0.

- [ ] **Step 7: Clean up the test directory**

```bash
rm -rf /tmp/skill-install-test
```

---

## Self-review checklist

Run this against the spec at `docs/specs/2026-05-02-omnifocus-skill-design.md` after completing all tasks.

**Spec coverage:**

| Spec requirement | Implemented in |
|---|---|
| Wrapper script with stdin and file-arg modes | Task 1 |
| Wrapper script exit codes (0/2/3/other) | Task 1, Steps 4–7 |
| Wrapper fails fast on OmniFocus-not-running | Task 1, deferred test note |
| 9 focused API reference files + FULL-REFERENCE | Task 2 |
| SKILL.md frontmatter with trigger-rich description | Task 3, Step 1 (frontmatter) |
| 8 "When to use" categories | Task 3, Step 1 (When to use) |
| "When NOT to use" with Obsidian boundary | Task 3, Step 1 (When NOT to use) |
| Heredoc and file-arg invocation patterns documented | Task 3, Step 1 (How to invoke) |
| Write-operations safety guidance | Task 3, Step 1 (Write operations) |
| Per-class write-field tables | Task 3, Step 1 (Available write operations) |
| Query template + accessors + lookup + search | Task 3, Step 1 (Writing queries) |
| API reference progressive-disclosure pointer | Task 3, Step 1 (API reference) |
| 16 carried-over query examples + new "completed in date range" | Task 3, Step 1 (Query patterns) |
| Tips | Task 3, Step 1 (Tips) |
| Manual verification scenarios | Task 4 |
| Public push and install test | Task 5 |

**Out-of-scope items** (intentionally NOT in this plan, per the spec):

- Defer-first capture rules → personal-workflow skill
- Tag-as-people-plus-1:1 conventions → personal-workflow skill
- No-flags convention → personal-workflow skill
- Proactive review nudges → personal-workflow skill
- Proactive capture nudges → personal-workflow skill
- Cross-tool routing (OF vs Obsidian) → personal-workflow skill
- Automated tests / CI → not shipped; manual verification only

**Placeholder scan:** none — every step has exact paths, exact commands, and exact content.

**Type/identifier consistency:** the wrapper interface (`scripts/eval.sh`), exit codes (0/2/3/other), and heredoc invocation pattern (`<<'EOF' ... EOF`) appear consistently across Task 1 (script implementation), Task 3 (SKILL.md examples), and Task 4 (verification).

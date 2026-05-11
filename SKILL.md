---
name: omnifocus
description: Read, write, and review the user's OmniFocus task database on macOS. Use whenever the user asks about what they need to do (today's agenda, overdue, flagged, inbox, by project/tag), what they've already completed ("did I do X", "have I logged Y", "when did I finish Z"), retrospective review over a time window ("what did I get done this week", weekly/monthly review, recent activity), decision support ("what should I work on next", "I have an hour, what's important"), planning ("help me break this down into tasks", "set up a project for X"), stale or needs-review surfacing ("what hasn't moved in a while", "what's due for review"), or when capturing/modifying tasks (add to inbox, complete, defer, reschedule, retag). The user keeps task/project/commitment data in OmniFocus and reference notes/knowledge in Obsidian — anything representing committed or completed work belongs here.
---

# OmniFocus

This skill lets you read and write OmniFocus data on the user's Mac by composing JavaScript (Omni Automation) and piping it through the bundled `scripts/eval.sh` wrapper to `osascript`. No server, no daemon, no network surface — direct local execution.

## Progressive disclosure

This file is the always-loaded core. Load these only when their topic comes up:

- `references/query-patterns.md` — canonical recipes for the common read/write operations (list inbox, find by tag, retrospective review, create task, mark complete, etc.). Load when you need the invocation for a specific operation.
- `docs/omnifocus-api/CHEATSHEET.md` and the per-class files — Omni Automation API reference. Load when you need details on a class or method not covered by the patterns file.

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
| 3 | OmniFocus could not be launched or did not become responsive. The wrapper auto-launches OmniFocus when it isn't already running, so this code only fires on a real failure (e.g., app missing, GUI unavailable). Surface it to the user. |
| other | osascript / Omni Automation error (e.g., JS syntax error, reference error) — see stderr for details |

On any non-zero exit, read stderr to diagnose.

### How the bridge works (technical)

`osascript -l JavaScript` on its own runs in JXA mode, which does NOT expose the Omni Automation globals (`flattenedTasks`, `inbox`, etc.). The wrapper bridges into Omni Automation by invoking `tell application "OmniFocus" to evaluate javascript "..."` from AppleScript. Your JS runs inside OmniFocus's own scripting engine, where the documented globals are available.

You don't need to do anything special — just write standard Omni Automation JavaScript. The wrapper handles the bridge and the string-escaping.

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
- Global accessors are available directly: `inbox`, `flattenedTasks`, `flattenedProjects`, etc. — no `Application()` or `document` prefix needed (the wrapper bridges into OmniFocus's Omni Automation engine for you).
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

## Query and write patterns — load `references/query-patterns.md`

For canonical recipes covering the common operations, load `references/query-patterns.md`:

- **Read:** list inbox, list all projects, find by tag, search by name, find overdue, find flagged, list a project's tasks, list all tags, list all folders, find due soon, completed in a date range (retrospective review).
- **Write:** create task in inbox, create task in a project, mark complete, set due date, add a tag, create a project.

Don't reinvent the invocation when one of these is what's needed — load the patterns file.

## Tips

- **Limit results:** for large databases, use `.slice(0, N)` to limit output. Many users have thousands of tasks.
- **Check for null:** many properties can be null (`dueDate`, `deferDate`, `containingProject`, etc.). Always check before calling methods on them.
- **Date formatting:** use `.toISOString()` on `Date` objects for consistent JSON serialization.
- **Tag and project lookup:** use `tagNamed("x")` / `projectNamed("x")` for exact match (returns the object or null); use `tagsMatching("x")` / `projectsMatching("x")` for substring match (returns an array).
- **Error handling:** on non-zero exit from `scripts/eval.sh`, read stderr. Exit code 3 means OmniFocus could not be launched or did not become responsive — surface that to the user, don't try to work around it. The wrapper auto-launches OmniFocus when it isn't running, so first invocations after a reboot may take an extra second or two. Other non-zero codes typically mean a JS error in your query.
- **Identifying tasks reliably:** when modifying tasks, prefer matching by `id.primaryKey` if you have it. Matching by `name` can match the wrong task if names aren't unique.

# Query and write patterns

Load when you need a concrete example for a specific OmniFocus operation. The SKILL.md has the query template, global accessors, lookup methods, and write-operation API summary; this file has the canonical recipes — copy and adapt.

## Two gotchas to know before composing queries

### `flattenedTasks` and `tag.tasks` contain phantom project-root entries

Every project surfaces inside `flattenedTasks` as a "task" whose `id.primaryKey === containingProject.id.primaryKey`. The same phantom appears in `tag.tasks` if the project itself is tagged. These entries are *projects*, not work items, but they inherit a `taskStatus` (typically `Blocked` while any child of the project is still open) and will pollute task queries — e.g. a `Blocked` count over `flattenedTasks` will lump real blocked tasks together with every active project. Filter them out:

```javascript
function isProjectRoot(t) {
  return t.containingProject != null
      && t.id.primaryKey === t.containingProject.id.primaryKey;
}
```

`proj.flattenedTasks` and `proj.tasks` (scoped to a single project) do *not* include the root — the leak is only in the global `flattenedTasks` and in `tag.tasks`. The recipes below apply this filter wherever it matters.

### `projectNamed` / `tagNamed` / `folderNamed` / `taskNamed` only check the top level

These built-in lookups do not recurse: `projectNamed("X")` only matches projects directly under the database root, not those inside folders; `tagNamed("X")` only matches top-level tags, not nested ones; same for folders and tasks. When a match isn't at the top, they silently return `null`.

For reliable lookups regardless of nesting, use `flattenedXxx.find(...)`:

```javascript
var proj   = flattenedProjects.find(p => p.name === "My Project");
var tag    = flattenedTags.find(tg => tg.name === "urgent");
var folder = flattenedFolders.find(f => f.name === "Areas");
var task   = flattenedTasks.find(t => t.name === "Buy groceries");
```

The recipes below use these patterns rather than the top-level-only helpers.

### `.name` is `undefined` on `Task.Status` and `Project.Status` members

`Task.Status.Available.name` is `undefined`, not `"Available"` — same for every other enum value. Naively writing `t.taskStatus.name` in a result object causes `JSON.stringify` to silently drop the field. Use identity comparison instead:

```javascript
function taskStatusName(t) {
  var s = t.taskStatus;
  if (s === Task.Status.Available) return "Available";
  if (s === Task.Status.Blocked) return "Blocked";
  if (s === Task.Status.Next) return "Next";
  if (s === Task.Status.Completed) return "Completed";
  if (s === Task.Status.Dropped) return "Dropped";
  if (s === Task.Status.DueSoon) return "DueSoon";
  if (s === Task.Status.Overdue) return "Overdue";
  return "Unknown";
}
function projectStatusName(p) {
  var s = p.status;
  if (s === Project.Status.Active) return "Active";
  if (s === Project.Status.OnHold) return "OnHold";
  if (s === Project.Status.Done) return "Done";
  if (s === Project.Status.Dropped) return "Dropped";
  return "Unknown";
}
```

Recipes below inline these helpers wherever they emit a status field.

## List inbox tasks

```bash
scripts/eval.sh <<'EOF'
JSON.stringify(
  inbox
    .filter(t => !t.effectivelyCompleted && !t.effectivelyDropped)
    .map(t => ({ name: t.name, id: t.id.primaryKey, flagged: t.flagged }))
)
EOF
```

The `inbox` accessor returns tasks that have *ever* been captured to inbox — including completed and dropped ones that haven't been processed out. When the user asks "what's in my inbox?" they almost always mean live items, so filter with `!t.effectivelyCompleted && !t.effectivelyDropped`. Same applies anywhere you read from `inbox`.

## List all projects

```bash
scripts/eval.sh <<'EOF'
function projectStatusName(p) {
  var s = p.status;
  if (s === Project.Status.Active) return "Active";
  if (s === Project.Status.OnHold) return "OnHold";
  if (s === Project.Status.Done) return "Done";
  if (s === Project.Status.Dropped) return "Dropped";
  return "Unknown";
}
JSON.stringify(flattenedProjects.map(p => ({ name: p.name, status: projectStatusName(p), id: p.id.primaryKey })))
EOF
```

## Find tasks by tag

```bash
scripts/eval.sh <<'EOF'
function isProjectRoot(t) {
  return t.containingProject != null
      && t.id.primaryKey === t.containingProject.id.primaryKey;
}
var tag = flattenedTags.find(tg => tg.name === "work");
JSON.stringify(
  tag
    ? tag.tasks
        .filter(t => !isProjectRoot(t))
        .map(t => ({ name: t.name, id: t.id.primaryKey, due: t.dueDate ? t.dueDate.toISOString() : null }))
    : []
)
EOF
```

`tag.tasks` includes project-root phantoms when the project itself is tagged; the filter strips them. `tagNamed("work")` would miss nested tags, so we use `flattenedTags.find(...)`.

## Search for tasks by name

```bash
scripts/eval.sh <<'EOF'
function isProjectRoot(t) {
  return t.containingProject != null
      && t.id.primaryKey === t.containingProject.id.primaryKey;
}
JSON.stringify(
  flattenedTasks
    .filter(t => !isProjectRoot(t))
    .filter(t => t.name.toLowerCase().includes("report"))
    .map(t => ({ name: t.name, id: t.id.primaryKey, project: t.containingProject ? t.containingProject.name : null }))
)
EOF
```

## Find overdue tasks

```bash
scripts/eval.sh <<'EOF'
function isProjectRoot(t) {
  return t.containingProject != null
      && t.id.primaryKey === t.containingProject.id.primaryKey;
}
JSON.stringify(
  flattenedTasks
    .filter(t => !isProjectRoot(t))
    .filter(t => t.taskStatus === Task.Status.Overdue)
    .map(t => ({ name: t.name, due: t.effectiveDueDate ? t.effectiveDueDate.toISOString() : null, project: t.containingProject ? t.containingProject.name : null }))
)
EOF
```

## Find flagged tasks

```bash
scripts/eval.sh <<'EOF'
function isProjectRoot(t) {
  return t.containingProject != null
      && t.id.primaryKey === t.containingProject.id.primaryKey;
}
JSON.stringify(
  flattenedTasks
    .filter(t => !isProjectRoot(t))
    .filter(t => t.effectiveFlagged && !t.completed)
    .map(t => ({ name: t.name, id: t.id.primaryKey, due: t.dueDate ? t.dueDate.toISOString() : null }))
)
EOF
```

## List tasks in a specific project

```bash
scripts/eval.sh <<'EOF'
function taskStatusName(t) {
  var s = t.taskStatus;
  if (s === Task.Status.Available) return "Available";
  if (s === Task.Status.Blocked) return "Blocked";
  if (s === Task.Status.Next) return "Next";
  if (s === Task.Status.Completed) return "Completed";
  if (s === Task.Status.Dropped) return "Dropped";
  if (s === Task.Status.DueSoon) return "DueSoon";
  if (s === Task.Status.Overdue) return "Overdue";
  return "Unknown";
}
var proj = flattenedProjects.find(p => p.name === "My Project");
JSON.stringify(proj ? proj.flattenedTasks.map(t => ({ name: t.name, status: taskStatusName(t), completed: t.completed })) : [])
EOF
```

`proj.flattenedTasks` does not include the project root, so no `isProjectRoot` filter is needed here. `projectNamed("My Project")` would miss projects nested in folders, so we use `flattenedProjects.find(...)`.

## List all tags

```bash
scripts/eval.sh <<'EOF'
function isProjectRoot(t) {
  return t.containingProject != null
      && t.id.primaryKey === t.containingProject.id.primaryKey;
}
JSON.stringify(flattenedTags.map(tg => ({
  name: tg.name,
  id: tg.id.primaryKey,
  taskCount: tg.tasks.filter(t => !isProjectRoot(t)).length
})))
EOF
```

`tg.tasks` counts the project root if the project itself is tagged; the filter keeps the count to real tasks.

## List all folders

```bash
scripts/eval.sh <<'EOF'
JSON.stringify(flattenedFolders.map(f => ({ name: f.name, id: f.id.primaryKey, projectCount: f.projects.length })))
EOF
```

## Get tasks due soon

```bash
scripts/eval.sh <<'EOF'
function isProjectRoot(t) {
  return t.containingProject != null
      && t.id.primaryKey === t.containingProject.id.primaryKey;
}
JSON.stringify(
  flattenedTasks
    .filter(t => !isProjectRoot(t))
    .filter(t => t.taskStatus === Task.Status.DueSoon)
    .map(t => ({ name: t.name, due: t.effectiveDueDate ? t.effectiveDueDate.toISOString() : null }))
)
EOF
```

## Completed tasks in a date range (retrospective review)

```bash
scripts/eval.sh <<'EOF'
function isProjectRoot(t) {
  return t.containingProject != null
      && t.id.primaryKey === t.containingProject.id.primaryKey;
}
var start = new Date("2026-04-25T00:00:00");
var end = new Date("2026-05-02T00:00:00");
JSON.stringify(
  flattenedTasks
    .filter(t => !isProjectRoot(t))
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

## Create a new task in inbox

```bash
scripts/eval.sh <<'EOF'
var t = new Task("Buy groceries", inbox.beginning);
JSON.stringify({ name: t.name, id: t.id.primaryKey })
EOF
```

## Create a task in a specific project

```bash
scripts/eval.sh <<'EOF'
var proj = flattenedProjects.find(p => p.name === "My Project");
if (!proj) { JSON.stringify({ error: "project not found" }); }
else {
  var t = new Task("Write report", proj);
  JSON.stringify({ name: t.name, id: t.id.primaryKey, project: t.containingProject.name });
}
EOF
```

## Mark a task complete

```bash
scripts/eval.sh <<'EOF'
function isProjectRoot(t) {
  return t.containingProject != null
      && t.id.primaryKey === t.containingProject.id.primaryKey;
}
var t = flattenedTasks.find(t => !isProjectRoot(t) && t.name === "Buy groceries");
if (t) {
  t.markComplete();
  JSON.stringify({ name: t.name, completed: t.completed });
} else {
  JSON.stringify({ error: "task not found" });
}
EOF
```

The `isProjectRoot` guard prevents accidentally matching a project whose name equals the task name (e.g. marking the "Buy groceries" project complete instead of a task by that name). For best reliability, prefer `Task.byIdentifier(id)` when you have the primaryKey.

## Set due date on a task

```bash
scripts/eval.sh <<'EOF'
function isProjectRoot(t) {
  return t.containingProject != null
      && t.id.primaryKey === t.containingProject.id.primaryKey;
}
var t = flattenedTasks.find(t => !isProjectRoot(t) && t.name === "Write report");
if (t) {
  t.dueDate = new Date("2026-06-01T17:00:00");
  JSON.stringify({ name: t.name, due: t.dueDate.toISOString() });
} else {
  JSON.stringify({ error: "task not found" });
}
EOF
```

## Add a tag to a task

```bash
scripts/eval.sh <<'EOF'
function isProjectRoot(t) {
  return t.containingProject != null
      && t.id.primaryKey === t.containingProject.id.primaryKey;
}
var t = flattenedTasks.find(t => !isProjectRoot(t) && t.name === "Write report");
var tag = flattenedTags.find(tg => tg.name === "urgent");
if (t && tag) {
  t.addTag(tag);
  JSON.stringify({ name: t.name, tags: t.tags.map(tg => tg.name) });
} else {
  JSON.stringify({ error: "task or tag not found" });
}
EOF
```

## Create a new project

```bash
scripts/eval.sh <<'EOF'
var p = new Project("Q2 Planning");
JSON.stringify({ name: p.name, id: p.id.primaryKey })
EOF
```

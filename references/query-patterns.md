# Query and write patterns

Load when you need a concrete example for a specific OmniFocus operation. The SKILL.md has the query template, global accessors, lookup methods, and write-operation API summary; this file has the canonical recipes — copy and adapt.

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
JSON.stringify(flattenedProjects.map(p => ({ name: p.name, status: p.status.name, id: p.id.primaryKey })))
EOF
```

## Find tasks by tag

```bash
scripts/eval.sh <<'EOF'
var tag = tagNamed("work");
JSON.stringify(tag ? tag.tasks.map(t => ({ name: t.name, id: t.id.primaryKey, due: t.dueDate ? t.dueDate.toISOString() : null })) : [])
EOF
```

## Search for tasks by name

```bash
scripts/eval.sh <<'EOF'
JSON.stringify(flattenedTasks.filter(t => t.name.toLowerCase().includes("report")).map(t => ({ name: t.name, id: t.id.primaryKey, project: t.containingProject ? t.containingProject.name : null })))
EOF
```

## Find overdue tasks

```bash
scripts/eval.sh <<'EOF'
JSON.stringify(flattenedTasks.filter(t => t.taskStatus === Task.Status.Overdue).map(t => ({ name: t.name, due: t.effectiveDueDate ? t.effectiveDueDate.toISOString() : null, project: t.containingProject ? t.containingProject.name : null })))
EOF
```

## Find flagged tasks

```bash
scripts/eval.sh <<'EOF'
JSON.stringify(flattenedTasks.filter(t => t.effectiveFlagged && !t.completed).map(t => ({ name: t.name, id: t.id.primaryKey, due: t.dueDate ? t.dueDate.toISOString() : null })))
EOF
```

## List tasks in a specific project

```bash
scripts/eval.sh <<'EOF'
var proj = projectNamed("My Project");
JSON.stringify(proj ? proj.flattenedTasks.map(t => ({ name: t.name, status: t.taskStatus.name, completed: t.completed })) : [])
EOF
```

## List all tags

```bash
scripts/eval.sh <<'EOF'
JSON.stringify(flattenedTags.map(tg => ({ name: tg.name, id: tg.id.primaryKey, taskCount: tg.tasks.length })))
EOF
```

## List all folders

```bash
scripts/eval.sh <<'EOF'
JSON.stringify(flattenedFolders.map(f => ({ name: f.name, id: f.id.primaryKey, projectCount: f.projects.length })))
EOF
```

## Get tasks due soon

```bash
scripts/eval.sh <<'EOF'
JSON.stringify(flattenedTasks.filter(t => t.taskStatus === Task.Status.DueSoon).map(t => ({ name: t.name, due: t.effectiveDueDate ? t.effectiveDueDate.toISOString() : null })))
EOF
```

## Completed tasks in a date range (retrospective review)

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
var proj = projectNamed("My Project");
var t = new Task("Write report", proj);
JSON.stringify({ name: t.name, id: t.id.primaryKey, project: t.containingProject.name })
EOF
```

## Mark a task complete

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

## Set due date on a task

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

## Add a tag to a task

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

## Create a new project

```bash
scripts/eval.sh <<'EOF'
var p = new Project("Q2 Planning");
JSON.stringify({ name: p.name, id: p.id.primaryKey })
EOF
```

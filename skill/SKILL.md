# ShipSheet Skill

Manage local task lists with shipsheet CLI. Use when asked to track tasks, create todo lists, or manage a ship sheet.

## When to Use

- User wants to track tasks or todos locally
- User needs a ship sheet for project management
- User wants to export tasks to Kanban or Google Sheets
- User asks to "add a task", "list tasks", "mark done", etc.

## Commands

### Add Task
```bash
npx shipsheet add "Task title" -p <priority> -t "tag1,tag2" -d "description" --due YYYY-MM-DD
```

Options:
- `-p, --priority`: low, medium, high, critical
- `-t, --tags`: Comma-separated tags
- `-d, --description`: Task description
- `--due`: Due date

### List Tasks
```bash
npx shipsheet list
npx shipsheet ls -s <status> -p <priority> -t <tag>
```

### Update Task
```bash
npx shipsheet update <id> -t "New title" -s <status> -p <priority>
```

### Move Task Status
```bash
npx shipsheet move <id> <status>
npx shipsheet done <id>
```

Statuses: `todo`, `in-progress`, `done`, `blocked`

### Remove Task
```bash
npx shipsheet rm <id>
```

### Export Tasks
```bash
npx shipsheet export -f <format> -o <output-file>
```

Formats: `json`, `csv`, `kanban`, `markdown`, `sheets`

## Examples

```bash
# Add high priority task with tags
npx shipsheet add "Fix auth bug" -p critical -t "bug,auth"

# List only in-progress tasks
npx shipsheet ls -s in-progress

# Mark task done (use first few chars of ID)
npx shipsheet done mkwbb

# Export to CSV for Google Sheets
npx shipsheet export -f csv -o tasks.csv
```

## File Location

Tasks are stored in `tasks.json` in the current directory.

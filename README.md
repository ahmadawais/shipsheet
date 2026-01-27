# shipsheet

CLI for managing a local `tasks.json` ship sheet - exportable to Kanban or Google Sheets.

## Install

```bash
npm install -g shipsheet
# or
npx shipsheet
```

## Usage

```bash
# Add tasks
ss add "Build authentication" -p high -t "feature,backend" --due 2026-02-01
ss add "Fix login bug" -d "Users can't login with SSO" -p critical

# List tasks
ss list                    # All tasks
ss ls -s in-progress       # Filter by status
ss ls -p high              # Filter by priority
ss ls -t feature           # Filter by tag

# Manage tasks
ss show <id>               # Show task details
ss update <id> -t "New title" -p medium
ss move <id> in-progress   # Move to status
ss done <id>               # Mark as done
ss rm <id>                 # Remove task

# Export
ss export                  # JSON (default)
ss export -f csv           # CSV for spreadsheets
ss export -f kanban        # Kanban board format
ss export -f sheets        # Google Sheets array format
ss export -f markdown      # Markdown format
ss export -f csv -o tasks.csv  # Save to file
```

## Task Structure

```json
{
  "id": "mkwbbi25gbew2",
  "title": "Build authentication",
  "description": "Optional description",
  "status": "todo",
  "priority": "high",
  "tags": ["feature", "backend"],
  "dueDate": "2026-02-01",
  "createdAt": "2026-01-27T08:00:00.000Z",
  "updatedAt": "2026-01-27T08:00:00.000Z"
}
```

## Statuses

- `todo` - Not started
- `in-progress` - Currently working
- `done` - Completed
- `blocked` - Blocked by something

## Priorities

- `critical` - 🔴 Drop everything
- `high` - 🟠 Important
- `medium` - 🟡 Normal (default)
- `low` - 🟢 When time permits

## Export Formats

| Format | Use Case |
|--------|----------|
| `json` | Full data backup, API integration |
| `csv` | Google Sheets, Excel import |
| `kanban` | Kanban board tools (Trello, Notion) |
| `sheets` | Google Sheets API (2D array) |
| `markdown` | Documentation, GitHub issues |

## AI Skills

Add shipsheet as a skill for AI coding agents:

```bash
npx skills ahmadawais/shipsheet
```

This teaches AI agents how to use shipsheet commands in your projects.

## License

MIT

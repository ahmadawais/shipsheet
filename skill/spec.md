# ShipSheet Specification

## Overview

ShipSheet is a CLI tool for managing local task lists stored in `tasks.json`. It provides a simple interface for task management with export capabilities for Kanban boards and Google Sheets.

## Data Model

### ShipSheet (Root)
```typescript
interface ShipSheet {
  name: string;           // Sheet name
  version: string;        // Schema version
  tasks: Task[];          // Array of tasks
  createdAt: string;      // ISO timestamp
  updatedAt: string;      // ISO timestamp
}
```

### Task
```typescript
interface Task {
  id: string;             // Unique identifier (base36 timestamp + random)
  title: string;          // Task title (required)
  description?: string;   // Optional description
  status: TaskStatus;     // Current status
  priority: TaskPriority; // Priority level
  tags?: string[];        // Optional tags array
  dueDate?: string;       // Optional due date (YYYY-MM-DD)
  createdAt: string;      // ISO timestamp
  updatedAt: string;      // ISO timestamp
}

type TaskStatus = 'todo' | 'in-progress' | 'done' | 'blocked';
type TaskPriority = 'low' | 'medium' | 'high' | 'critical';
```

## CLI Commands

| Command | Alias | Description |
|---------|-------|-------------|
| `add <title>` | - | Add new task |
| `list` | `ls` | List all tasks |
| `show <id>` | - | Show task details |
| `update <id>` | - | Update task properties |
| `move <id> <status>` | - | Change task status |
| `done <id>` | - | Mark task as done |
| `remove <id>` | `rm` | Delete task |
| `export` | - | Export to various formats |

## Export Formats

### JSON
Full `tasks.json` content with all metadata.

### CSV
```
ID,Title,Description,Status,Priority,Tags,Due Date,Created,Updated
```

### Kanban
```json
{
  "todo": [...],
  "in-progress": [...],
  "done": [...],
  "blocked": [...]
}
```

### Google Sheets (2D Array)
```json
[
  ["ID", "Title", "Description", "Status", "Priority", "Tags", "Due Date", "Created", "Updated"],
  ["id1", "Task 1", "", "todo", "high", "tag1, tag2", "", "2026-01-27", "2026-01-27"]
]
```

### Markdown
Kanban-style markdown with priority indicators and grouped by status.

## ID Matching

Task IDs support partial matching - you can use the first few characters of an ID to reference a task (e.g., `mkwbb` instead of `mkwbbi25gbew2`).

## File Storage

- Location: `./tasks.json` in current working directory
- Format: Pretty-printed JSON (2-space indent)
- Auto-created on first task add

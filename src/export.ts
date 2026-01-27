import type { Task } from './types.js';
import { loadSheet } from './store.js';

export function toCSV(): string {
  const sheet = loadSheet();
  const headers = ['ID', 'Title', 'Description', 'Status', 'Priority', 'Tags', 'Due Date', 'Created', 'Updated'];
  const rows = sheet.tasks.map((t) => [
    t.id,
    `"${t.title.replace(/"/g, '""')}"`,
    `"${(t.description || '').replace(/"/g, '""')}"`,
    t.status,
    t.priority,
    `"${(t.tags || []).join(', ')}"`,
    t.dueDate || '',
    t.createdAt,
    t.updatedAt,
  ]);

  return [headers.join(','), ...rows.map((r) => r.join(','))].join('\n');
}

export function toKanban(): Record<string, Task[]> {
  const sheet = loadSheet();
  return {
    todo: sheet.tasks.filter((t) => t.status === 'todo'),
    'in-progress': sheet.tasks.filter((t) => t.status === 'in-progress'),
    done: sheet.tasks.filter((t) => t.status === 'done'),
    blocked: sheet.tasks.filter((t) => t.status === 'blocked'),
  };
}

export function toGoogleSheetsFormat(): string[][] {
  const sheet = loadSheet();
  const headers = ['ID', 'Title', 'Description', 'Status', 'Priority', 'Tags', 'Due Date', 'Created', 'Updated'];
  const rows = sheet.tasks.map((t) => [
    t.id,
    t.title,
    t.description || '',
    t.status,
    t.priority,
    (t.tags || []).join(', '),
    t.dueDate || '',
    t.createdAt,
    t.updatedAt,
  ]);

  return [headers, ...rows];
}

export function toJSON(): string {
  const sheet = loadSheet();
  return JSON.stringify(sheet, null, 2);
}

export function toMarkdown(): string {
  const kanban = toKanban();
  let md = '# Ship Sheet\n\n';

  for (const [status, tasks] of Object.entries(kanban)) {
    md += `## ${status.charAt(0).toUpperCase() + status.slice(1)}\n\n`;
    if (tasks.length === 0) {
      md += '_No tasks_\n\n';
    } else {
      for (const task of tasks) {
        const priority = task.priority === 'critical' ? '🔴' : task.priority === 'high' ? '🟠' : task.priority === 'medium' ? '🟡' : '🟢';
        md += `- ${priority} **${task.title}**`;
        if (task.description) md += ` - ${task.description}`;
        if (task.dueDate) md += ` (Due: ${task.dueDate})`;
        md += '\n';
      }
      md += '\n';
    }
  }

  return md;
}

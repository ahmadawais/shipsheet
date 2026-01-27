#!/usr/bin/env node

import { Command } from 'commander';
import { writeFileSync } from 'node:fs';
import { addTask, listTasks, updateTask, removeTask, moveTask, getTask } from './store.js';
import { toCSV, toKanban, toJSON, toMarkdown, toGoogleSheetsFormat } from './export.js';
import type { TaskStatus, TaskPriority } from './types.js';

const program = new Command();

program
  .name('shipsheet')
  .description('CLI for managing a local tasks.json ship sheet')
  .version('1.0.0');

program
  .command('add <title>')
  .description('Add a new task')
  .option('-d, --description <desc>', 'Task description')
  .option('-s, --status <status>', 'Task status (todo, in-progress, done, blocked)', 'todo')
  .option('-p, --priority <priority>', 'Task priority (low, medium, high, critical)', 'medium')
  .option('-t, --tags <tags>', 'Comma-separated tags')
  .option('--due <date>', 'Due date (YYYY-MM-DD)')
  .action((title, opts) => {
    const task = addTask(title, {
      description: opts.description,
      status: opts.status as TaskStatus,
      priority: opts.priority as TaskPriority,
      tags: opts.tags?.split(',').map((t: string) => t.trim()),
      dueDate: opts.due,
    });
    console.log(`✓ Added task: ${task.title} [${task.id}]`);
  });

program
  .command('list')
  .alias('ls')
  .description('List all tasks')
  .option('-s, --status <status>', 'Filter by status')
  .option('-p, --priority <priority>', 'Filter by priority')
  .option('-t, --tag <tag>', 'Filter by tag')
  .action((opts) => {
    const tasks = listTasks({
      status: opts.status as TaskStatus,
      priority: opts.priority as TaskPriority,
      tag: opts.tag,
    });

    if (tasks.length === 0) {
      console.log('No tasks found.');
      return;
    }

    const statusIcon: Record<TaskStatus, string> = {
      todo: '○',
      'in-progress': '◐',
      done: '●',
      blocked: '✕',
    };

    const priorityColor: Record<TaskPriority, string> = {
      critical: '\x1b[31m',
      high: '\x1b[33m',
      medium: '\x1b[36m',
      low: '\x1b[90m',
    };

    const reset = '\x1b[0m';

    for (const task of tasks) {
      const icon = statusIcon[task.status];
      const color = priorityColor[task.priority];
      const tags = task.tags?.length ? ` [${task.tags.join(', ')}]` : '';
      const due = task.dueDate ? ` (due: ${task.dueDate})` : '';
      console.log(`${icon} ${color}${task.id.slice(0, 7)}${reset} ${task.title}${tags}${due}`);
    }
  });

program
  .command('show <id>')
  .description('Show task details')
  .action((id) => {
    const task = getTask(id);
    if (!task) {
      console.error(`Task not found: ${id}`);
      process.exit(1);
    }

    console.log(`ID:          ${task.id}`);
    console.log(`Title:       ${task.title}`);
    console.log(`Description: ${task.description || '-'}`);
    console.log(`Status:      ${task.status}`);
    console.log(`Priority:    ${task.priority}`);
    console.log(`Tags:        ${task.tags?.join(', ') || '-'}`);
    console.log(`Due:         ${task.dueDate || '-'}`);
    console.log(`Created:     ${task.createdAt}`);
    console.log(`Updated:     ${task.updatedAt}`);
  });

program
  .command('update <id>')
  .description('Update a task')
  .option('-t, --title <title>', 'New title')
  .option('-d, --description <desc>', 'New description')
  .option('-s, --status <status>', 'New status')
  .option('-p, --priority <priority>', 'New priority')
  .option('--tags <tags>', 'New tags (comma-separated)')
  .option('--due <date>', 'New due date')
  .action((id, opts) => {
    const updates: Record<string, unknown> = {};
    if (opts.title) updates.title = opts.title;
    if (opts.description) updates.description = opts.description;
    if (opts.status) updates.status = opts.status;
    if (opts.priority) updates.priority = opts.priority;
    if (opts.tags) updates.tags = opts.tags.split(',').map((t: string) => t.trim());
    if (opts.due) updates.dueDate = opts.due;

    const task = updateTask(id, updates);
    if (!task) {
      console.error(`Task not found: ${id}`);
      process.exit(1);
    }
    console.log(`✓ Updated task: ${task.title}`);
  });

program
  .command('remove <id>')
  .alias('rm')
  .description('Remove a task')
  .action((id) => {
    const removed = removeTask(id);
    if (!removed) {
      console.error(`Task not found: ${id}`);
      process.exit(1);
    }
    console.log(`✓ Removed task`);
  });

program
  .command('move <id> <status>')
  .description('Move task to a status (todo, in-progress, done, blocked)')
  .action((id, status) => {
    const validStatuses = ['todo', 'in-progress', 'done', 'blocked'];
    if (!validStatuses.includes(status)) {
      console.error(`Invalid status. Use: ${validStatuses.join(', ')}`);
      process.exit(1);
    }
    const task = moveTask(id, status as TaskStatus);
    if (!task) {
      console.error(`Task not found: ${id}`);
      process.exit(1);
    }
    console.log(`✓ Moved "${task.title}" to ${status}`);
  });

program
  .command('done <id>')
  .description('Mark task as done')
  .action((id) => {
    const task = moveTask(id, 'done');
    if (!task) {
      console.error(`Task not found: ${id}`);
      process.exit(1);
    }
    console.log(`✓ Completed: ${task.title}`);
  });

program
  .command('export')
  .description('Export tasks to various formats')
  .option('-f, --format <format>', 'Export format (csv, json, kanban, markdown, sheets)', 'json')
  .option('-o, --output <file>', 'Output file (prints to stdout if not specified)')
  .action((opts) => {
    let output: string;

    switch (opts.format) {
      case 'csv':
        output = toCSV();
        break;
      case 'kanban':
        output = JSON.stringify(toKanban(), null, 2);
        break;
      case 'markdown':
      case 'md':
        output = toMarkdown();
        break;
      case 'sheets':
        output = JSON.stringify(toGoogleSheetsFormat(), null, 2);
        break;
      case 'json':
      default:
        output = toJSON();
    }

    if (opts.output) {
      writeFileSync(opts.output, output);
      console.log(`✓ Exported to ${opts.output}`);
    } else {
      console.log(output);
    }
  });

program.parse();

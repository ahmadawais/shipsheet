import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import type { ShipSheet, Task, TaskStatus, TaskPriority } from './types.js';

const TASKS_FILE = 'tasks.json';

function getTasksPath(): string {
  return join(process.cwd(), TASKS_FILE);
}

function createDefaultSheet(): ShipSheet {
  return {
    name: 'Ship Sheet',
    version: '1.0.0',
    tasks: [],
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
}

export function loadSheet(): ShipSheet {
  const path = getTasksPath();
  if (!existsSync(path)) {
    const sheet = createDefaultSheet();
    saveSheet(sheet);
    return sheet;
  }
  const data = readFileSync(path, 'utf-8');
  return JSON.parse(data) as ShipSheet;
}

export function saveSheet(sheet: ShipSheet): void {
  sheet.updatedAt = new Date().toISOString();
  writeFileSync(getTasksPath(), JSON.stringify(sheet, null, 2));
}

export function generateId(): string {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
}

export function addTask(
  title: string,
  options: {
    description?: string;
    status?: TaskStatus;
    priority?: TaskPriority;
    tags?: string[];
    dueDate?: string;
  } = {}
): Task {
  const sheet = loadSheet();
  const now = new Date().toISOString();
  const task: Task = {
    id: generateId(),
    title,
    description: options.description,
    status: options.status || 'todo',
    priority: options.priority || 'medium',
    tags: options.tags,
    createdAt: now,
    updatedAt: now,
    dueDate: options.dueDate,
  };
  sheet.tasks.push(task);
  saveSheet(sheet);
  return task;
}

export function listTasks(filter?: {
  status?: TaskStatus;
  priority?: TaskPriority;
  tag?: string;
}): Task[] {
  const sheet = loadSheet();
  let tasks = sheet.tasks;

  if (filter?.status) {
    tasks = tasks.filter((t) => t.status === filter.status);
  }
  if (filter?.priority) {
    tasks = tasks.filter((t) => t.priority === filter.priority);
  }
  if (filter?.tag) {
    tasks = tasks.filter((t) => t.tags?.includes(filter.tag!));
  }

  return tasks;
}

export function getTask(id: string): Task | undefined {
  const sheet = loadSheet();
  return sheet.tasks.find((t) => t.id === id || t.id.startsWith(id));
}

export function updateTask(
  id: string,
  updates: Partial<Omit<Task, 'id' | 'createdAt'>>
): Task | null {
  const sheet = loadSheet();
  const index = sheet.tasks.findIndex((t) => t.id === id || t.id.startsWith(id));
  if (index === -1) return null;

  sheet.tasks[index] = {
    ...sheet.tasks[index],
    ...updates,
    updatedAt: new Date().toISOString(),
  };
  saveSheet(sheet);
  return sheet.tasks[index];
}

export function removeTask(id: string): boolean {
  const sheet = loadSheet();
  const index = sheet.tasks.findIndex((t) => t.id === id || t.id.startsWith(id));
  if (index === -1) return false;

  sheet.tasks.splice(index, 1);
  saveSheet(sheet);
  return true;
}

export function moveTask(id: string, status: TaskStatus): Task | null {
  return updateTask(id, { status });
}

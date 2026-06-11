#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const workerPath = path.join(root, "src", "index.ts");
const schemaPath = path.join(root, "init-db.sql");

const workerSource = fs.readFileSync(workerPath, "utf8");
const schemaSource = fs.readFileSync(schemaPath, "utf8");

function findCreateTableColumns(source) {
  const tables = new Map();
  const re = /CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+([A-Za-z_][\w]*)/gi;
  let match;
  while ((match = re.exec(source)) !== null) {
    const tableName = match[1];
    const open = source.indexOf("(", re.lastIndex);
    if (open === -1) continue;
    const close = findMatchingParen(source, open);
    if (close === -1) continue;
    const body = source.slice(open + 1, close);
    tables.set(tableName, columnNames(body));
  }
  return tables;
}

function findMatchingParen(source, openIndex) {
  let depth = 0;
  let quote = null;
  for (let i = openIndex; i < source.length; i += 1) {
    const ch = source[i];
    const prev = source[i - 1];
    if (quote) {
      if (ch === quote && prev !== "\\") quote = null;
      continue;
    }
    if (ch === "'" || ch === '"') {
      quote = ch;
      continue;
    }
    if (ch === "(") depth += 1;
    if (ch === ")") {
      depth -= 1;
      if (depth === 0) return i;
    }
  }
  return -1;
}

function splitTopLevelComma(value) {
  const parts = [];
  let depth = 0;
  let quote = null;
  let start = 0;
  for (let i = 0; i < value.length; i += 1) {
    const ch = value[i];
    const prev = value[i - 1];
    if (quote) {
      if (ch === quote && prev !== "\\") quote = null;
      continue;
    }
    if (ch === "'" || ch === '"') {
      quote = ch;
      continue;
    }
    if (ch === "(") depth += 1;
    if (ch === ")") depth -= 1;
    if (ch === "," && depth === 0) {
      parts.push(value.slice(start, i));
      start = i + 1;
    }
  }
  parts.push(value.slice(start));
  return parts;
}

function columnNames(tableBody) {
  const columns = new Set();
  const constraints = new Set([
    "PRIMARY",
    "FOREIGN",
    "UNIQUE",
    "CHECK",
    "CONSTRAINT",
  ]);
  for (const part of splitTopLevelComma(tableBody)) {
    const trimmed = part.trim();
    const name = trimmed.match(/^"?([A-Za-z_][\w]*)"?\b/)?.[1];
    if (!name || constraints.has(name.toUpperCase())) continue;
    columns.add(name);
  }
  return columns;
}

function findIndexes(source) {
  return new Set(
    Array.from(
      source.matchAll(/CREATE\s+INDEX\s+IF\s+NOT\s+EXISTS\s+([A-Za-z_][\w]*)/gi),
      (m) => m[1],
    ),
  );
}

function findAddedColumns(source) {
  const added = new Map();
  for (const match of source.matchAll(
    /ALTER\s+TABLE\s+([A-Za-z_][\w]*)\s+ADD\s+COLUMN\s+([A-Za-z_][\w]*)/gi,
  )) {
    const [, table, column] = match;
    if (!added.has(table)) added.set(table, new Set());
    added.get(table).add(column);
  }
  return added;
}

function mergeAddedColumns(tables, added) {
  const merged = new Map(Array.from(tables, ([k, v]) => [k, new Set(v)]));
  for (const [table, columns] of added) {
    if (!merged.has(table)) merged.set(table, new Set());
    for (const column of columns) merged.get(table).add(column);
  }
  return merged;
}

function missingItems(required, actual) {
  return Array.from(required).filter((item) => !actual.has(item)).sort();
}

const workerTables = mergeAddedColumns(
  findCreateTableColumns(workerSource),
  findAddedColumns(workerSource),
);
const schemaTables = mergeAddedColumns(
  findCreateTableColumns(schemaSource),
  findAddedColumns(schemaSource),
);
const workerIndexes = findIndexes(workerSource);
const schemaIndexes = findIndexes(schemaSource);

const errors = [];
const missingTables = missingItems(workerTables.keys(), schemaTables);
if (missingTables.length > 0) {
  errors.push(`Missing tables in init-db.sql: ${missingTables.join(", ")}`);
}

const missingIndexes = missingItems(workerIndexes, schemaIndexes);
if (missingIndexes.length > 0) {
  errors.push(`Missing indexes in init-db.sql: ${missingIndexes.join(", ")}`);
}

for (const [table, requiredColumns] of workerTables) {
  const actualColumns = schemaTables.get(table) ?? new Set();
  const missingColumns = missingItems(requiredColumns, actualColumns);
  if (missingColumns.length > 0) {
    errors.push(
      `Missing columns in init-db.sql for ${table}: ${missingColumns.join(", ")}`,
    );
  }
}

if (errors.length > 0) {
  console.error("D1 schema drift detected:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("D1 schema migration coverage OK");

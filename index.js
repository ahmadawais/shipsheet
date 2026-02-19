#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);

function resolveShipeeetBin() {
  const packageJsonPath = require.resolve("shipeeet/package.json");
  const packageJson = JSON.parse(readFileSync(packageJsonPath, "utf8"));
  const { bin } = packageJson;

  let relativeBin = null;
  if (typeof bin === "string") {
    relativeBin = bin;
  } else if (bin && typeof bin === "object") {
    relativeBin =
      bin.shipeeet ||
      bin.shipsheet ||
      Object.values(bin).find((value) => typeof value === "string");
  }

  if (!relativeBin) {
    throw new Error('Could not resolve a bin entry from "shipeeet".');
  }

  const resolvedBin = path.resolve(path.dirname(packageJsonPath), relativeBin);
  if (!existsSync(resolvedBin)) {
    throw new Error(`Resolved shipeeet bin was not found: ${resolvedBin}`);
  }

  return resolvedBin;
}

function main() {
  let shipeeetBin;
  try {
    shipeeetBin = resolveShipeeetBin();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`Failed to load shipeeet: ${message}`);
    process.exit(1);
  }

  const result = spawnSync(process.execPath, [shipeeetBin, ...process.argv.slice(2)], {
    stdio: "inherit",
    env: process.env,
  });

  if (result.error) {
    console.error(`Failed to run shipeeet: ${result.error.message}`);
    process.exit(1);
  }

  process.exit(result.status ?? 1);
}

main();

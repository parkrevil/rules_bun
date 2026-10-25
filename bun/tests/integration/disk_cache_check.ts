// Checks the execution log of the second build in CI's windows-disk-cache job
// (FR-027, research G1; tasks.md T113): the npm test targets were built with
// one --disk_cache under a first and then a second --output_base, and every
// spawn of the second build that consumes a package store link must be a disk
// cache hit.
//
//   bazel run //bun/tests/integration:disk_cache_check -- <execution log JSON file>
//
// Bazel 9.2.0 writes --execution_log_json_file as SpawnExec messages
// (src/main/protobuf/spawn.proto) printed by protobuf's JsonFormat one after
// another without a separator (MessageOutputStreamWrapper.JsonOutputStreamWrapper);
// the fields read are `mnemonic`, `targetLabel`, `inputs[].path` and `cacheHit`.

import { readFileSync } from "node:fs";
import { isAbsolute, join } from "node:path";

export interface SpawnExec {
  mnemonic?: string;
  targetLabel?: string;
  inputs?: { path: string }[];
  cacheHit?: boolean;
}

/** The JSON objects of a concatenated JSON stream. */
export function parseStream(text: string): SpawnExec[] {
  const values: SpawnExec[] = [];
  let depth = 0;
  let start = -1;
  let inString = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inString) {
      if (ch === "\\") i++;
      else if (ch === '"') inString = false;
    } else if (ch === '"') {
      inString = true;
    } else if (ch === "{") {
      if (depth++ === 0) start = i;
    } else if (ch === "}") {
      if (--depth === 0) values.push(JSON.parse(text.slice(start, i + 1)));
    }
  }
  if (depth !== 0 || inString) throw new Error("the execution log ends inside a JSON value");
  return values;
}

// A package link of a target's copy tree: `<name>.bun/<package>/node_modules/<alias>`
// or `<name>.bun/.store/<store name>/node_modules/<dependency>` (research R5).
const STORE_LINK = /(?:^|\/)[^/]+\.bun\/(?:[^/]+\/)*node_modules\//;

/** The spawns that consume a store link, and those of them that missed the cache. */
export function check(spawns: SpawnExec[]): { consuming: SpawnExec[]; misses: SpawnExec[] } {
  const consuming = spawns.filter((s) => (s.inputs ?? []).some((f) => STORE_LINK.test(f.path.split("\\").join("/"))));
  return { consuming, misses: consuming.filter((s) => s.cacheHit !== true) };
}

if (import.meta.main) {
  const [file] = process.argv.slice(2);
  if (file === undefined) {
    console.error("usage: disk_cache_check <execution log JSON file>");
    process.exit(2);
  }
  const path = isAbsolute(file) ? file : join(process.env.BUILD_WORKING_DIRECTORY ?? process.cwd(), file);
  const { consuming, misses } = check(parseStream(readFileSync(path, "utf8")));
  if (consuming.length === 0) {
    console.error(`disk_cache_check: no spawn in ${path} consumes a store link, so nothing was checked`);
    process.exit(1);
  }
  for (const s of misses) console.error(`disk_cache_check: ${s.mnemonic} of ${s.targetLabel} consumes a store link and missed the disk cache`);
  console.log(`disk_cache_check: ${consuming.length - misses.length} of ${consuming.length} spawns consuming a store link were disk cache hits`);
  process.exit(misses.length === 0 ? 0 : 1);
}

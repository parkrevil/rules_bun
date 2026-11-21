// Canary C-ROWORDER (feature 006, research Part 4 L29): the pinned Bun writes the `packages` rows
// sorted by the depth of their parent path, then the parent path, then the name (LOCK L506–L508,
// L646), the order the loader's "a later row of equal evidence wins" (LOCK L2993) is read in, and
// a frozen install keeps the rows in that order.

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const READER = "_find_resolution in bun/private/bun_lockfile.bzl";

// A key's parent path and name: "./lib/y/x" is ["./lib/y", "x"], depth 2.
function split(key: string): { depth: number; parent: string; name: string } {
  const parts = key.split("/");
  const segments: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    // "./<name>" (an unlinked workspace) and "@scope/name" are one segment each.
    const prefix = parts[i] === "." ? `./` : "";
    if (prefix) i++;
    const name = parts[i].startsWith("@") ? `${parts[i]}/${parts[++i]}` : parts[i];
    segments.push(prefix + name);
  }
  return { depth: segments.length - 1, parent: segments.slice(0, -1).join("/"), name: segments[segments.length - 1] };
}

function before(a: string, b: string): boolean {
  const l = split(a);
  const r = split(b);
  if (l.depth !== r.depth) return l.depth < r.depth;
  if (l.parent !== r.parent) return l.parent < r.parent;
  return l.name < r.name;
}

const FILES = {
  "package.json": manifest({
    name: "c-roworder",
    workspaces: ["packages/*"],
    dependencies: { lib: "npm:a@1.0.0", "@scope/lib": "npm:c@1.0.0", b: "1.0.0", x: "2.0.0", y: "npm:q@2.0.0" },
  }),
  "packages/lib/package.json": manifest({ name: "lib", version: "1.0.0", dependencies: { b: "2.0.0", x: "2.0.0", y: "1.0.0" } }),
  "packages/scoped/package.json": manifest({ name: "@scope/lib", version: "1.0.0", dependencies: { b: "2.0.0", q: "1.0.0" } }),
  "packages/app/package.json": manifest({ name: "app", version: "1.0.0", dependencies: { lib: "workspace:*", "@scope/lib": "workspace:*" } }),
};

// Moves the last row of `packages` to the front.
function lastRowFirst(text: string): string {
  const lines = text.split("\n");
  const start = lines.indexOf('  "packages": {');
  const rows = lines.flatMap((line, i) => (i > start && /^ {4}"/.test(line) ? [i] : []));
  // Rows are separated by an empty line; the last row's is the line before it.
  const [, last] = lines.splice(rows[rows.length - 1] - 1, 2);
  lines.splice(rows[0], 0, last, "");
  return lines.join("\n");
}

test("packages rows are sorted by parent depth, parent path and name", async () => {
  const first = await runInstall(FILES);
  const { lock } = await runInstall(
    { ...FILES, "bun.lock": first.text },
    // Red: the lockfile's last row is moved to the front.
    { dir: first.dir, frozenLockfile: true, alter: red({ lockfile: lastRowFirst }) },
  );
  const keys = Object.keys(lock.packages);
  if (keys.length < 10 || !keys.some((key) => key.startsWith("./"))) canaryFail("C-ROWORDER", "packages rows", READER, LOCKFILE_SOURCE, keys);
  for (let i = 1; i < keys.length; i++) {
    if (!before(keys[i - 1], keys[i])) canaryFail("C-ROWORDER", "order of packages rows", READER, LOCKFILE_SOURCE, keys);
  }
});

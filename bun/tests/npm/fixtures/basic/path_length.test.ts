// The longest path in the package store of a target's copy tree (research G8),
// printed for research G8, and the deepest fixture module loaded through the
// target: on Windows that path is longer than MAX_PATH (260 characters), which
// Windows long-path support covers (research G11).

import { expect, test } from "bun:test";
import { readdirSync, realpathSync } from "node:fs";
import { dirname, join, sep } from "node:path";

function longest(dir: string): string {
  let found = dir;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    const candidate = entry.isDirectory() ? longest(path) : path;
    if (candidate.length > found.length) found = candidate;
  }
  return found;
}

test("the longest store path of the copy tree", () => {
  const deep = realpathSync(dirname(require.resolve("deep/package.json")));
  const marker = `${sep}.store${sep}`;
  const store = deep.slice(0, deep.indexOf(marker) + marker.length - 1);
  const path = longest(store);
  console.log(`longest store path (${path.length} characters): ${path}`);
  expect(path).toContain(`${sep}deep${sep}`);
});

test("the deepest fixture module loads through the target", () => {
  // deep's index.js requires lib/level0_directory_name/…/leaf_module_file.js,
  // the file at the longest store path.
  expect(require("deep")).toBe("deep");
});

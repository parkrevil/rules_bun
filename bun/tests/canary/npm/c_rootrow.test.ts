// Canary C-ROOTROW (feature 006, research Part 4 L38): for a workspace member that depends on the
// root package, the pinned Bun writes the root as a `packages` row
// ["<name>@root:", { "bin": … }] (LOCK writer L751–L780: the root's `bin` or `binDir`, `{}` when it
// has none), and a frozen install loads that row only with an object in slot 1 (LOCK L2612–L2627).
// _entry in bun/private/lockfile.bzl reads slot 1 of a `root:` row only to refuse what Bun refuses
// (T170), so the row must stay in that form.

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const READER = "_entry in bun/private/lockfile.bzl";

const FILES = {
  "package.json": manifest({ name: "c-rootrow", bin: { "root-bin": "cli.js" }, workspaces: ["packages/*"] }),
  "cli.js": 'console.log("root-bin");\n',
  "packages/w/package.json": manifest({ name: "w", version: "1.0.0", dependencies: { "c-rootrow": "workspace:*" } }),
};

test("the root package's row holds its bins in slot 1", async () => {
  const first = await runInstall(FILES);
  let lock: Record<string, any>;
  try {
    ({ lock } = await runInstall(
      { ...FILES, "bun.lock": first.text },
      {
        dir: first.dir,
        frozenLockfile: true,
        // Red: slot 1 of the root: row is removed, which Bun's loader refuses.
        alter: red({
          lockfile: (text) => {
            const removed = text.replace(/("c-rootrow@root:"), \{[^\]]*\}\]/, "$1]");
            if (removed === text) throw new Error('red: the lockfile has no "c-rootrow@root:" row to alter');
            return removed;
          },
        }),
      },
    ));
  } catch (error) {
    canaryFail("C-ROOTROW", "root: row", READER, LOCKFILE_SOURCE, String(error));
  }
  const row = lock.packages["c-rootrow"];
  if (!Array.isArray(row) || row.length !== 2 || row[0] !== "c-rootrow@root:" || JSON.stringify(row[1]) !== '{"bin":{"root-bin":"cli.js"}}') {
    canaryFail("C-ROOTROW", "root: row", READER, LOCKFILE_SOURCE, row);
  }
});

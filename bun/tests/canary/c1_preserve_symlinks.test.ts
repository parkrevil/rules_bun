// Canary C1 (FR-028): pins that Bun resolves a relative import from the real path
// of the importing file even with --preserve-symlinks and
// --preserve-symlinks-main (oven-sh/bun#43689). When this fails, revisit the
// per-target copy tree and the load guard.

import { test } from "bun:test";
import { mkdirSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const MESSAGE =
  "Bun now resolves imports beside a symbolic link: revisit the per-target copy tree and the load guard; " +
  "https://github.com/oven-sh/bun/issues/43689, https://github.com/oven-sh/bun/pull/36757";

test("an import of a linked file resolves from the link target's directory", () => {
  const root = join(process.env.TEST_TMPDIR!, "c1");
  const target = join(root, "target");
  const linkDir = join(root, "link");
  mkdirSync(target, { recursive: true });
  mkdirSync(linkDir, { recursive: true });
  writeFileSync(join(target, "a.ts"), 'import { b } from "./b.ts";\nconsole.log(b);\n');
  writeFileSync(join(target, "b.ts"), 'export const b = "target";\n');
  writeFileSync(join(linkDir, "b.ts"), 'export const b = "link";\n');

  const link = join(linkDir, "a.ts");
  try {
    symlinkSync(join(target, "a.ts"), link);
  } catch (error) {
    console.log(`C1 not asserted: this runner cannot create a symbolic link (${error})`);
    return;
  }

  const result = Bun.spawnSync([process.execPath, "--preserve-symlinks", "--preserve-symlinks-main", link], {
    cwd: root,
  });
  const output = result.stdout.toString().trim();
  if (output !== "target") {
    throw new Error(`${MESSAGE}; observed output ${JSON.stringify(output)}, exit ${result.exitCode}`);
  }
});

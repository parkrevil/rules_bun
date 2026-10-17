// Canary C2 (FR-028): pins that `bun test` with CI=true fails a new
// toMatchSnapshot() and still creates a header-only __snapshots__/<file>.snap
// (oven-sh/bun#44531). When this fails, revisit that snapshot tests are
// unsupported (FR-016b, G2).

import { test } from "bun:test";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const MESSAGE =
  "Bun's snapshot behavior under CI changed: revisit that snapshot tests are unsupported (FR-016b, G2); " +
  "https://github.com/oven-sh/bun/issues/44531";

test("a new snapshot under CI fails and leaves a header-only .snap file", () => {
  const root = join(process.env.TEST_TMPDIR!, "c2");
  mkdirSync(root, { recursive: true });
  writeFileSync(
    join(root, "s.test.ts"),
    'import { expect, test } from "bun:test";\ntest("snap", () => { expect({ a: 1 }).toMatchSnapshot(); });\n',
  );

  const result = Bun.spawnSync([process.execPath, "test", "./s.test.ts"], {
    cwd: root,
    env: { ...process.env, CI: "true" },
  });
  const snap = join(root, "__snapshots__", "s.test.ts.snap");
  const content = existsSync(snap) ? readFileSync(snap, "utf8") : null;
  const headerOnly =
    content !== null && content.split("\n").every((line) => line === "" || line.startsWith("//"));
  if (result.exitCode === 0 || !headerOnly) {
    throw new Error(`${MESSAGE}; observed exit ${result.exitCode}, .snap content ${JSON.stringify(content)}`);
  }
});

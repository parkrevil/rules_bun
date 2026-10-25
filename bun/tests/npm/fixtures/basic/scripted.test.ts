// FR-023: no lifecycle script runs. scripted's postinstall would write
// postinstall-ran into its package directory, and the root package.json names
// it in trustedDependencies.

import { expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import scripted from "scripted";

test("the package loads and its postinstall did not run", () => {
  expect(scripted).toBeDefined();
  const dir = dirname(require.resolve("scripted"));
  // Windows paths use "\\".
  expect(dir.replaceAll("\\", "/")).toContain(".store/scripted@1.0.0/node_modules/scripted");
  expect(existsSync(join(dir, "postinstall-ran"))).toBe(false);
});

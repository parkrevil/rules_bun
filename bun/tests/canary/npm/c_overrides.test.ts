// Canary C-OVERRIDES (FR-006, research L18, R9): the lockfile form Bun 1.4.4
// writes for each manifest override form rules_bun accepts, which
// normalize_overrides reproduces before comparing.

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const ACCESS = "overrides";
const READER = "normalize_overrides in bun/private/overrides.bzl";

const CASES: [string, Record<string, unknown>, unknown][] = [
  ["flat", { overrides: { b: "2.0.0" } }, { b: "2.0.0" }],
  ["a>b", { overrides: { "a>b": "2.0.0" } }, { a: { b: "2.0.0" } }],
  ["object form with \".\"", { overrides: { a: { ".": "1.0.0", b: "2.0.0" } } }, { a: { ".": "1.0.0", b: "2.0.0" } }],
  ["range parent", { overrides: { "a@^1.0.0>b": "2.0.0" } }, { "a@^1.0.0": { b: "2.0.0" } }],
  ["resolutions path", { resolutions: { "a/b": "2.0.0" } }, { a: { b: "2.0.0" } }],
  ["resolutions glob path", { resolutions: { "**/a/**/b": "2.0.0" } }, { a: { b: "2.0.0" } }],
];

for (const [name, fields, expected] of CASES) {
  test(`the ${name} form is written as ${JSON.stringify(expected)}`, async () => {
    const { lock } = await runInstall(
      { "package.json": manifest({ name: "c-overrides", dependencies: { a: "1.0.0" }, ...fields }) },
      // Red: the override targets c instead of b.
      { alter: red({ files: (f) => ({ "package.json": f["package.json"].replaceAll(/"(\*\*\/a\/\*\*\/|a\/|a>|a@\^1\.0\.0>)?b"/g, '"$1c"') }) }) },
    );
    if (JSON.stringify(lock.overrides) !== JSON.stringify(expected)) canaryFail("C-OVERRIDES", ACCESS, READER, LOCKFILE_SOURCE, lock.overrides);
  });
}

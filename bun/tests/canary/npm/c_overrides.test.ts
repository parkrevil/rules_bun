// Canary C-OVERRIDES (FR-006, research L18, R9): pins the lockfile form Bun 1.4.4 writes for each
// manifest override form, which the comparison parses into rules from both sides (feature 007,
// research R8).

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const ACCESS = "overrides";
const READER = "override_map_parse_append and override_map_changed in bun/private/bun_override_map.bzl, and _parse_overrides in bun/private/bun_lockfile.bzl";

const CASES: [string, Record<string, unknown>, unknown][] = [
  ["flat", { overrides: { b: "2.0.0" } }, { b: "2.0.0" }],
  ["a>b", { overrides: { "a>b": "2.0.0" } }, { a: { b: "2.0.0" } }],
  ["object form with \".\"", { overrides: { a: { ".": "1.0.0", b: "2.0.0" } } }, { a: { ".": "1.0.0", b: "2.0.0" } }],
  ["range parent", { overrides: { "a@^1.0.0>b": "2.0.0" } }, { "a@^1.0.0": { b: "2.0.0" } }],
  ["resolutions path", { resolutions: { "a/b": "2.0.0" } }, { a: { b: "2.0.0" } }],
  ["resolutions glob path", { resolutions: { "**/a/**/b": "2.0.0" } }, { a: { b: "2.0.0" } }],
  // T177: a `$<name>` reference is written as the specifier the root declares, and an object
  // nested one level deeper than the parent's is not written.
  ["$ reference", { dependencies: { a: "1.0.0", b: "1.0.0" }, overrides: { b: "$b" } }, { b: "1.0.0" }],
  ["object nested in a parent's object", { overrides: { a: { b: "2.0.0", x: { y: "1.0.0" } } } }, { a: { b: "2.0.0" } }],
  // T179: the root's `$<name>` is its parsed package's first dependency of the name, dev entries
  // sorted first, and a name only in `peerDependenciesMeta` is a peer "*".
  ["$ reference to dependencies and devDependencies", { dependencies: { a: "1.0.0", b: "1.0.0" }, devDependencies: { b: "2.0.0" }, overrides: { b: "$b" } }, { b: "2.0.0" }],
  ["$ reference to a peerDependenciesMeta name", { peerDependenciesMeta: { b: { optional: true } }, overrides: { c: "$b" } }, { c: "*" }],
  ["range key", { overrides: { "b@^1.0.0": "2.0.0" } }, { "b@^1.0.0": { ".": "2.0.0" } }],
  ["object form with \".\" only", { overrides: { b: { ".": "2.0.0" } } }, { b: "2.0.0" }],
  ["parent with \".\" and a pnpm child", { overrides: { a: "1.0.0", "a>b": "2.0.0" } }, { a: { ".": "1.0.0", b: "2.0.0" } }],
  ["resolutions double-star prefix", { resolutions: { "**/b": "2.0.0" } }, { b: "2.0.0" }],
  ["resolutions parent glob", { resolutions: { "a/**/b": "2.0.0" } }, { a: { b: "2.0.0" } }],
  ["overrides path", { overrides: { "a/b": "2.0.0" } }, { a: { b: "2.0.0" } }],
  ["pnpm delimiter before a space", { overrides: { "a> b": "2.0.0" } }, { a: { b: "2.0.0" } }],
  ["pnpm delimiter after a space", { overrides: { "a > b": "2.0.0" } }, { "a > b": "2.0.0" }],
  ["range key with >=", { overrides: { "b@>=1.0.0": "2.0.0" } }, { "b@>=1.0.0": { ".": "2.0.0" } }],
  ["range key with npm: prefix", { overrides: { "b@npm:^1.0.0": "2.0.0" } }, { "b@^1.0.0": { ".": "2.0.0" } }],
  ["resolutions pnpm delimiter", { resolutions: { "a>b": "2.0.0" } }, { a: { b: "2.0.0" } }],
  ["skipped non-string value in overrides", { overrides: { q: 2, b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped empty value in overrides", { overrides: { q: "", b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped dash value in overrides", { overrides: { q: "-", b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped empty key in overrides", { overrides: { "": "2.0.0", b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped patch value in overrides", { overrides: { q: "patch:q@1.0.0#patches/q.patch", b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped comment key in overrides", { overrides: { "//": "note", b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped selector-error key @s in overrides", { overrides: { "@s": "2.0.0", b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped selector-error key b@ in overrides", { overrides: { "b@": "2.0.0", b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped selector-error key a//b in overrides", { overrides: { "a//b": "2.0.0", b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped selector-error key a/** in overrides", { overrides: { "a/**": "2.0.0", b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped selector-error key a>b>c in overrides", { overrides: { "a>b>c": "2.0.0", b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped selector-error key a/b/c in overrides", { overrides: { "a/b/c": "2.0.0", b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped non-string value in resolutions", { resolutions: { q: 2, b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped empty value in resolutions", { resolutions: { q: "", b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped dash value in resolutions", { resolutions: { q: "-", b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped empty key in resolutions", { resolutions: { "": "2.0.0", b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped patch value in resolutions", { resolutions: { q: "patch:q@1.0.0#patches/q.patch", b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped comment key in resolutions", { resolutions: { "//": "note", b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped selector-error key @s in resolutions", { resolutions: { "@s": "2.0.0", b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped selector-error key b@ in resolutions", { resolutions: { "b@": "2.0.0", b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped selector-error key a//b in resolutions", { resolutions: { "a//b": "2.0.0", b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped selector-error key a/** in resolutions", { resolutions: { "a/**": "2.0.0", b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped selector-error key a>b>c in resolutions", { resolutions: { "a>b>c": "2.0.0", b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped selector-error key a/b/c in resolutions", { resolutions: { "a/b/c": "2.0.0", b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped non-string value under a parent", { overrides: { a: { q: 2 }, b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped empty value under a parent", { overrides: { a: { q: "" }, b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped dash value under a parent", { overrides: { a: { q: "-" }, b: "2.0.0" } }, { b: "2.0.0" }],
  ["skipped comment key under a parent", { overrides: { a: { "//": "note" }, b: "2.0.0" } }, { b: "2.0.0" }],
  // Review of 2026-11-25 (research Part 6 D5): forms the unit tests read from Bun's source; a rule
  // Bun skips is listed next to a kept `b`, so the red has something to change.
  ["parent range that is no selector range", { overrides: { "a@latest>b": "2.0.0", b: "2.0.0" } }, { b: "2.0.0" }],
  ["target range that is no selector range", { overrides: { "b@latest": "2.0.0", b: "2.0.0" } }, { b: "2.0.0" }],
  ["parent object with a range that is no selector range", { overrides: { "a@latest": { b: "2.0.0" }, b: "2.0.0" } }, { b: "2.0.0" }],
  ["alias target range", { overrides: { "b@npm:other@^1.0.0": "2.0.0" } }, { "b@npm:other@^1.0.0": { ".": "2.0.0" } }],
  ["later flat rule replacing an earlier one", { resolutions: { b: "1.0.0", "**/b": "2.0.0" } }, { b: "2.0.0" }],
  ["later scoped rule replacing an earlier one", { resolutions: { "a>b": "1.0.0", "a/b": "2.0.0" } }, { a: { b: "2.0.0" } }],
  ["pnpm child key carrying a parent under an object", { overrides: { a: { "x>b": "2.0.0" }, b: "2.0.0" } }, { b: "2.0.0" }],
  ["path child key carrying a parent under an object", { overrides: { a: { "c/b": "2.0.0" }, b: "2.0.0" } }, { b: "2.0.0" }],
  ["patch value under a parent", { overrides: { a: { q: "patch:q@1.0.0#patches/q.patch" }, b: "2.0.0" } }, { b: "2.0.0" }],
];

for (const [name, fields, expected] of CASES) {
  test(`the ${name} form is written as ${JSON.stringify(expected)}`, async () => {
    const { lock } = await runInstall(
      { "package.json": manifest({ name: "c-overrides", dependencies: { a: "1.0.0" }, ...fields }) },
      // Red: the override targets c instead of b.
      { alter: red({ files: (f) => ({ "package.json": f["package.json"].replaceAll(/"(\*\*\/a\/\*\*\/|\*\*\/|a\/\*\*\/|a\/|a> |a > |a>|a@\^1\.0\.0>)?b(@[^"]*)?"/g, '"$1c$2"') }) }) },
    );
    if (!Bun.deepEquals(lock.overrides, expected)) canaryFail("C-OVERRIDES", ACCESS, READER, LOCKFILE_SOURCE, lock.overrides);
  });
}

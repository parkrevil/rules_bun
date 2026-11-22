// Unit tests of graph.ts's comparison (research R8, contract "Failure text").

import { expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, symlinkSync, writeFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { compare, type Graph, projectDifference, readBunGraph } from "./graph.ts";

const entry = (name: string, version: string, links: Record<string, string> = {}) => ({ name, version, links });

test("graphs equal up to entry order and indices are equal", () => {
  const ruleset: Graph = {
    holders: { "": { a: "e:0", b: "e:1" } },
    entries: [entry("a", "1.0.0", { b: "e:1" }), entry("b", "1.0.0")],
  };
  const bun: Graph = {
    holders: { "": { a: "e:1", b: "e:0" } },
    entries: [entry("b", "1.0.0"), entry("a", "1.0.0", { b: "e:0" })],
  };
  expect(compare("p", ruleset, bun)).toBeUndefined();
});

test("one entry against two entries of one name@version with different peer bindings differ", () => {
  // Bun: p@1.0.0 twice, once with q@1.0.0 and once with q@2.0.0.
  const bun: Graph = {
    holders: { "": { u: "e:0", v: "e:1" } },
    entries: [
      entry("u", "1.0.0", { p: "e:2" }),
      entry("v", "1.0.0", { p: "e:3" }),
      entry("p", "1.0.0", { q: "e:4" }),
      entry("p", "1.0.0", { q: "e:5" }),
      entry("q", "1.0.0"),
      entry("q", "2.0.0"),
    ],
  };
  // Ruleset: one p@1.0.0 with q@1.0.0 for both.
  const ruleset: Graph = {
    holders: { "": { u: "e:0", v: "e:1" } },
    entries: [entry("u", "1.0.0", { p: "e:2" }), entry("v", "1.0.0", { p: "e:2" }), entry("p", "1.0.0", { q: "e:3" }), entry("q", "1.0.0")],
  };
  expect(compare("p", ruleset, bun)).toBe(
    'p: p@1.0.0 links "q" to q@1.0.0, Bun links it to q@2.0.0',
  );
});

test("entry counts count: two identical entries against one", () => {
  const bun: Graph = { holders: { "": { a: "e:0", b: "e:1" } }, entries: [entry("a", "1.0.0", { x: "e:2" }), entry("b", "1.0.0", { x: "e:2" }), entry("x", "1.0.0")] };
  const ruleset: Graph = {
    holders: { "": { a: "e:0", b: "e:1" } },
    entries: [entry("a", "1.0.0", { x: "e:2" }), entry("b", "1.0.0", { x: "e:3" }), entry("x", "1.0.0"), entry("x", "1.0.0")],
  };
  expect(compare("p", ruleset, bun)).toBe(
    'p: x@1.0.0 is 2 entries in the ruleset, Bun installs it as 1: b@1.0.0 (reached from the root) links "x" to another entry of it than a@1.0.0 (reached from the root) links "x" to, Bun links both to one',
  );
});

test("entry counts count: one entry against two names both dependents and their other bindings (FR-012)", () => {
  const ruleset: Graph = {
    holders: { "": { a: "e:0", b: "e:1" } },
    entries: [entry("a", "1.0.0", { x: "e:2" }), entry("b", "1.0.0", { x: "e:2", y: "e:3" }), entry("x", "1.0.0"), entry("y", "1.0.0")],
  };
  const bun: Graph = {
    holders: { "": { a: "e:0", b: "e:1" } },
    entries: [entry("a", "1.0.0", { x: "e:2" }), entry("b", "1.0.0", { x: "e:3", y: "e:4" }), entry("x", "1.0.0"), entry("x", "1.0.0"), entry("y", "1.0.0")],
  };
  expect(compare("p", ruleset, bun)).toBe(
    'p: x@1.0.0 is 1 entries in the ruleset, Bun installs it as 2: b@1.0.0 (y → y@1.0.0, reached from the root) links "x" to the entry of it a@1.0.0 (reached from the root) links "x" to, Bun links them to two',
  );
});

test("entry counts count: two holders linking two entries against one name both holders (FR-012)", () => {
  const ruleset: Graph = { holders: { "": { x: "e:0" }, "packages/w": { x: "e:1" } }, entries: [entry("x", "1.0.0"), entry("x", "1.0.0")] };
  const bun: Graph = { holders: { "": { x: "e:0" }, "packages/w": { x: "e:0" } }, entries: [entry("x", "1.0.0")] };
  expect(compare("p", ruleset, bun)).toBe(
    'p: x@1.0.0 is 2 entries in the ruleset, Bun installs it as 1: workspace "packages/w" links "x" to another entry of it than the root links "x" to, Bun links both to one',
  );
});

test("entry counts count: an extra entry no holder reaches is named as such", () => {
  const ruleset: Graph = { holders: { "": { a: "e:0" } }, entries: [entry("a", "1.0.0"), entry("a", "1.0.0")] };
  const bun: Graph = { holders: { "": { a: "e:0" } }, entries: [entry("a", "1.0.0")] };
  expect(compare("p", ruleset, bun)).toBe("p: a@1.0.0 is 2 entries in the ruleset, Bun installs it as 1: no holder reaches the ruleset's extra entry");
});

test("a holder linking a different target differs", () => {
  const bun: Graph = { holders: { "": { b: "e:0" } }, entries: [entry("b", "2.0.0")] };
  const ruleset: Graph = { holders: { "": { b: "e:0" } }, entries: [entry("b", "1.0.0")] };
  expect(compare("p", ruleset, bun)).toBe('p: the root links "b" to b@1.0.0, Bun links it to b@2.0.0');
});

test("a missing link differs", () => {
  const bun: Graph = { holders: { "": {}, "packages/w": { b: "e:0" } }, entries: [entry("b", "1.0.0")] };
  const ruleset: Graph = { holders: { "": {}, "packages/w": {} }, entries: [] };
  expect(compare("p", ruleset, bun)).toBe('p: workspace "packages/w" links "b" to no link, Bun links it to b@1.0.0');
});

test("an extra link differs", () => {
  const bun: Graph = { holders: { "": { a: "e:0" } }, entries: [entry("a", "1.0.0")] };
  const ruleset: Graph = { holders: { "": { a: "e:0" } }, entries: [entry("a", "1.0.0", { state: "e:1" }), entry("state", "1.0.0")] };
  expect(compare("p", ruleset, bun)).toBe('p: a@1.0.0 links "state" to state@1.0.0, Bun links it to no link');
});

test("a workspace target is compared by path", () => {
  const bun: Graph = { holders: { "": { u: "e:0" }, "packages/m": {} }, entries: [entry("u", "1.0.0", { m: "w:packages/m" })] };
  const ruleset: Graph = { holders: { "": { u: "e:0" }, "packages/m": {} }, entries: [entry("u", "1.0.0")] };
  expect(compare("p", ruleset, bun)).toBe('p: u@1.0.0 links "m" to no link, Bun links it to workspace "packages/m"');
});

test("a holder on one side only differs, naming its links and their bindings (FR-012)", () => {
  const bun: Graph = { holders: { "": {}, "packages/w": { b: "e:0" } }, entries: [entry("b", "1.0.0", { c: "e:1" }), entry("c", "1.0.0")] };
  const ruleset: Graph = { holders: { "": {} }, entries: [] };
  expect(compare("p", ruleset, bun)).toBe('p: workspace "packages/w" is a holder in Bun only: Bun links "b" to b@1.0.0 (c → c@1.0.0), the ruleset links it to no link');
});

test("a holder in the ruleset only names each of its links", () => {
  const ruleset: Graph = { holders: { "": {}, "packages/w": { a: "e:0", m: "w:" } }, entries: [entry("a", "1.0.0")] };
  const bun: Graph = { holders: { "": {} }, entries: [] };
  expect(compare("p", ruleset, bun)).toBe(
    'p: workspace "packages/w" is a holder in the ruleset only: the ruleset links "a" to a@1.0.0 and "m" to the root, Bun links them to no link',
  );
});

test("a holder on one side only without links says so", () => {
  const bun: Graph = { holders: { "": {}, "packages/w": {} }, entries: [] };
  const ruleset: Graph = { holders: { "": {} }, entries: [] };
  expect(compare("p", ruleset, bun)).toBe('p: workspace "packages/w" is a holder in Bun only and links nothing');
});

test("a package at no registry version is identified by its resolution", () => {
  // Bun's store directory of a `file:` package is not DOC-ISO's `<package>@<version>` form.
  const bun: Graph = { holders: { "": { local: "e:0" } }, entries: [{ ...entry("local", "1.0.0"), resolution: "file:local" }] };
  const ruleset: Graph = { holders: { "": { local: "e:0" } }, entries: [entry("local", "file:local")] };
  expect(compare("p", ruleset, bun)).toBeUndefined();
});

/** Writes the files of an isolated install as Bun lays it out: `links` maps a link's path to its
 * target, both relative to the project. */
function installed(files: Record<string, unknown>, links: Record<string, string>): string {
  const dir = mkdtempSync(join(process.env.TEST_TMPDIR!, "graph-"));
  for (const [path, value] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), typeof value === "string" ? value : JSON.stringify(value));
  }
  for (const [path, target] of Object.entries(links)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    symlinkSync(relative(dirname(join(dir, path)), join(dir, target)), join(dir, path), "dir");
  }
  return dir;
}

test("non-registry entries are compared by their resolution: two file: folders swapped differ (T172)", () => {
  // As the pinned Bun installs `"x": "file:./a", "y": "file:./b"`, two folders of one package name
  // and version: bun.lock rows `foo@file:a` and `foo@file:b`, store directories `foo@file+a` and
  // `foo@file+b` (research Part 7 E19). The ruleset links them the other way round.
  const dir = installed(
    {
      "bun.lock": {
        lockfileVersion: 1,
        workspaces: { "": { name: "t", dependencies: { x: "file:./a", y: "file:./b" } } },
        packages: { x: ["foo@file:a", {}], y: ["foo@file:b", {}] },
      },
      "node_modules/.bun/foo@file+a/node_modules/foo/package.json": { name: "foo", version: "1.0.0" },
      "node_modules/.bun/foo@file+b/node_modules/foo/package.json": { name: "foo", version: "1.0.0" },
    },
    { "node_modules/x": "node_modules/.bun/foo@file+a/node_modules/foo", "node_modules/y": "node_modules/.bun/foo@file+b/node_modules/foo" },
  );
  const bun = readBunGraph(dir, [""]);
  const ruleset: Graph = { holders: { "": { x: "e:0", y: "e:1" } }, entries: [entry("foo", "file:b"), entry("foo", "file:a")] };
  expect(compare("p", ruleset, bun)).toBe('p: the root links "x" to foo@file:b, Bun links it to foo@file:a');
  const same: Graph = { holders: { "": { x: "e:0", y: "e:1" } }, entries: [entry("foo", "file:a"), entry("foo", "file:b")] };
  expect(compare("p", same, bun)).toBeUndefined();
});

test("a store directory Bun bounds is read back to its resolution (T172)", () => {
  // The directory the pinned Bun names for `"@s/long": "file:./dir-<70 x>/c"` (research Part 7
  // E19): the first 63 bytes of `file+dir-…+c` and the wyhash of all of it.
  const path = `dir-${"x".repeat(70)}/c`;
  const store = `@s+long@file+dir-${"x".repeat(54)}+29f4eee30e89905a`;
  const dir = installed(
    {
      "bun.lock": {
        lockfileVersion: 1,
        workspaces: { "": { name: "t", dependencies: { "@s/long": `file:./${path}` } } },
        packages: { "@s/long": [`@s/long@file:${path}`, {}] },
      },
      [`node_modules/.bun/${store}/node_modules/@s/long/package.json`]: { name: "@s/long", version: "1.0.0" },
    },
    { "node_modules/@s/long": `node_modules/.bun/${store}/node_modules/@s/long` },
  );
  expect(readBunGraph(dir, [""]).entries).toEqual([{ name: "@s/long", version: "1.0.0", links: {}, resolution: `file:${path}` }]);
});

test("a local tarball's store directory is read back to its resolution (T175)", () => {
  // As the pinned Bun installs `"b": "file:loc-1.0.0.tgz"` (fixtures/conformance_local_tarball): the
  // bun.lock row `loc@loc-1.0.0.tgz`, the store directory `loc@loc-1.0.0.tgz+<the first 8 bytes of
  // its integrity>` (isolated_install.rs L1353–L1368).
  const store = "loc@loc-1.0.0.tgz+f3d5a20e448a231c";
  const dir = installed(
    {
      "bun.lock": {
        lockfileVersion: 2,
        workspaces: { "": { name: "t", dependencies: { b: "file:loc-1.0.0.tgz" } } },
        packages: { b: ["loc@loc-1.0.0.tgz", {}, "sha512-89WiDkSKIxyDT/+sD9LZSL9zQ0b8zjfjPV9Nnr8LZHsfg61iHXDASUKSNkRUE4zK7TwcFQWuEXiAT7FHNFHy2w=="] },
      },
      [`node_modules/.bun/${store}/node_modules/loc/package.json`]: { name: "loc", version: "1.0.0" },
    },
    { "node_modules/b": `node_modules/.bun/${store}/node_modules/loc` },
  );
  expect(readBunGraph(dir, [""]).entries).toEqual([{ name: "loc", version: "1.0.0", links: {}, resolution: "loc-1.0.0.tgz" }]);
});

test("a registry entry bound where Bun binds a non-registry one of its name and version differs (T127)", () => {
  // The root's foo is file:./vendor/foo, whose package.json says 1.0.0; d1 and d2 depend on the
  // registry's foo@1.0.0. The ruleset binds d2's foo to the root's file: foo.
  const bun: Graph = {
    holders: { "": { foo: "e:0", d1: "e:1", d2: "e:2" } },
    entries: [{ ...entry("foo", "1.0.0"), resolution: "file:vendor/foo" }, entry("d1", "1.0.0", { foo: "e:3" }), entry("d2", "1.0.0", { foo: "e:3" }), entry("foo", "1.0.0")],
  };
  const ruleset: Graph = {
    holders: { "": { foo: "e:0", d1: "e:1", d2: "e:2" } },
    entries: [entry("foo", "file:vendor/foo"), entry("d1", "1.0.0", { foo: "e:3" }), entry("d2", "1.0.0", { foo: "e:0" }), entry("foo", "1.0.0")],
  };
  expect(compare("p", ruleset, bun)).toBe('p: d2@1.0.0 links "foo" to foo@file:vendor/foo, Bun links it to foo@1.0.0');
});

test("an entry whose status fails analysis in the ruleset differs, named by the link that reaches it (FR-012)", () => {
  const bun: Graph = { holders: { "": { "ident-a": "e:0" } }, entries: [entry("ident-a", "1.0.0")] };
  const ruleset: Graph = {
    holders: { "": { "ident-a": "e:0" } },
    entries: [{ ...entry("ident-a", "1.0.0"), status: 'it needs the peer "state", which nothing provides' }],
  };
  expect(compare("p", ruleset, bun)).toBe(
    'p: the root links "ident-a" to ident-a@1.0.0, which fails analysis in the ruleset (it needs the peer "state", which nothing provides), Bun links it to ident-a@1.0.0 and installs it',
  );
});

test("an entry that fails analysis, reached through an entry, names the dependent and both sides' bindings (FR-012)", () => {
  const bun: Graph = {
    holders: { "": { u: "e:0", v: "e:1" } },
    entries: [entry("u", "1.0.0", { p: "e:2", w: "e:4" }), entry("v", "1.0.0", { p: "e:2" }), entry("p", "1.0.0", { q: "e:3" }), entry("q", "1.0.0"), entry("w", "1.0.0")],
  };
  const ruleset: Graph = {
    holders: { "": { u: "e:1", v: "e:2" } },
    entries: [
      { ...entry("p", "1.0.0", { q: "e:3" }), status: "S" },
      entry("u", "1.0.0", { p: "e:0", w: "e:4" }),
      entry("v", "1.0.0", { p: "e:0" }),
      entry("q", "1.0.0"),
      entry("w", "1.0.0"),
    ],
  };
  expect(compare("p", ruleset, bun)).toBe(
    'p: u@1.0.0 (w → w@1.0.0) links "p" to p@1.0.0 (q → q@1.0.0), which fails analysis in the ruleset (S), Bun links it to p@1.0.0 (q → q@1.0.0) and installs it',
  );
});

test("of two entries that fail analysis, the first one reached walking down from the holders is named", () => {
  const bun: Graph = { holders: { "": { a: "e:0", z: "e:2" } }, entries: [entry("a", "1.0.0", { x: "e:1" }), entry("x", "1.0.0"), entry("z", "1.0.0")] };
  const ruleset: Graph = {
    holders: { "": { a: "e:1", z: "e:2" } },
    entries: [{ ...entry("x", "1.0.0"), status: "S1" }, entry("a", "1.0.0", { x: "e:0" }), { ...entry("z", "1.0.0"), status: "S2" }],
  };
  expect(compare("p", ruleset, bun)).toBe('p: the root links "z" to z@1.0.0, which fails analysis in the ruleset (S2), Bun links it to z@1.0.0 and installs it');
});

test("an entry that fails analysis and no holder reaches is named as such", () => {
  const bun: Graph = { holders: { "": {} }, entries: [entry("a", "1.0.0")] };
  const ruleset: Graph = { holders: { "": {} }, entries: [{ ...entry("a", "1.0.0"), status: "S" }] };
  expect(compare("p", ruleset, bun)).toBe("p: a@1.0.0 fails analysis in the ruleset (S), Bun installs it: no holder reaches it");
});

test("an unfetched entry's status is excluded by ID-4, its links still compared", () => {
  const reason = "bun.lock records no integrity for it, so its download cannot be verified";
  const bun: Graph = { holders: { "": { a: "e:0" } }, entries: [entry("a", "1.0.0", { b: "e:1" }), entry("b", "1.0.0")] };
  const ruleset: Graph = {
    holders: { "": { a: "e:0" } },
    entries: [{ ...entry("a", "1.0.0", { b: "e:1" }), status: reason, unfetched: true }, entry("b", "1.0.0")],
  };
  expect(compare("p", ruleset, bun)).toBeUndefined();
  const unlinked: Graph = { holders: { "": { a: "e:0" } }, entries: [{ ...entry("a", "1.0.0"), status: reason, unfetched: true }] };
  expect(compare("p", unlinked, bun)).toBe('p: a@1.0.0 links "b" to no link, Bun links it to b@1.0.0');
});

test("a holder whose links reach two entries of one name@version in the ruleset differs", () => {
  // Bun links p@1.0.0 under two peer bindings; the ruleset links both too, but one target cannot
  // hold them (run.bzl `_check_unique`).
  const graph: Graph = {
    holders: { "": { p: "e:0", "q2-user": "e:2" } },
    entries: [entry("p", "1.0.0", { q: "e:1" }), entry("q", "1.0.0"), entry("q2-user", "1.0.0", { p: "e:3", q: "e:4" }), entry("p", "1.0.0", { q: "e:4" }), entry("q", "2.0.0")],
  };
  const conflicts = { "": { "p@1.0.0+0000000000000001": { "e:0": ["p"], "e:3": ["q2-user"] } } };
  expect(compare("p", { ...graph, conflicts }, graph)).toBe(
    "p: the root's links reach 2 entries of p@1.0.0+0000000000000001, which run.bzl fails analysis of in one target, while Bun links each: " +
      'p@1.0.0 (q → q@1.0.0) through "p"; p@1.0.0 (q → q@2.0.0) through "q2-user"',
  );
});

test("a conflicting entry several links of the holder reach names each of them", () => {
  const graph: Graph = {
    holders: { "packages/w": { p: "e:0", r: "e:2", u: "e:3" } },
    entries: [entry("p", "1.0.0", { q: "e:1" }), entry("q", "1.0.0"), entry("r", "1.0.0", { p: "e:0" }), entry("u", "1.0.0", { p: "e:4" }), entry("p", "1.0.0", { q: "e:5" }), entry("q", "2.0.0")],
  };
  const conflicts = { "packages/w": { "p@1.0.0+0000000000000001": { "e:0": ["p", "r"], "e:4": ["u"] } } };
  expect(compare("p", { ...graph, conflicts }, graph)).toBe(
    'p: workspace "packages/w"\'s links reach 2 entries of p@1.0.0+0000000000000001, which run.bzl fails analysis of in one target, while Bun links each: ' +
      'p@1.0.0 (q → q@1.0.0) through "p", "r"; p@1.0.0 (q → q@2.0.0) through "u"',
  );
});

test("a ruleset failure is the ruleset's, with either oracle (T167)", () => {
  const bun: Graph = { holders: { "": { a: "e:0" } }, entries: [entry("a", "1.0.0")] };
  const failed = { error: "rules_bun: p/bun.lock: broken" };
  const expected = "p: the ruleset fails (rules_bun: p/bun.lock: broken), Bun installs the lockfile";
  expect(projectDifference("p", failed, bun, "1.4.4")).toBe(expected);
  expect(projectDifference("p", failed, bun, "1.4.2")).toBe(expected);
});

test("a graph difference with Bun 1.4.2 as the oracle is a disagreement of the two Bun versions (FR-013)", () => {
  const bun: Graph = { holders: { "": { a: "e:0" } }, entries: [entry("a", "1.0.0"), entry("a", "2.0.0")] };
  const ruleset: Graph = { holders: { "": { a: "e:1" } }, entries: [entry("a", "1.0.0"), entry("a", "2.0.0")] };
  expect(projectDifference("p", ruleset, bun, "1.4.4")).toBe('p: the root links "a" to a@2.0.0, Bun links it to a@1.0.0');
  expect(projectDifference("p", ruleset, bun, "1.4.2")).toBe(
    'p: Bun 1.4.2 links this lockfile differently from Bun 1.4.4, which the ruleset follows (the root links "a" to a@2.0.0, Bun links it to a@1.0.0); the ruleset cannot follow both (constitution V)',
  );
  expect(projectDifference("p", bun, bun, "1.4.2")).toBeUndefined();
});

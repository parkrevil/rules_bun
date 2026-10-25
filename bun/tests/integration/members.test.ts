// Workspace members (FR-006, FR-015, US4-4, US4-5): the members the root
// package.json's globs match must be the lockfile's; adding or removing a
// member with bun.lock updated takes effect at the next evaluation without a
// change to the root package.json; npm_link_all_packages() belongs in a
// workspace package.

import { afterAll, expect, test } from "bun:test";
import { readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { rlocation } from "../support/spawn.ts";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";

const FIXTURES = "_main/bun/tests/npm/fixtures";
const inner = new Inner("members");
afterAll(() => inner.close());

// A fixture file, with the loopback port of the run that wrote it replaced.
const fixture = (path: string) =>
  readFileSync(rlocation(`${FIXTURES}/${path}`), "utf8").replaceAll(/http:\/\/127\.0\.0\.1:\d+/g, inner.registry.url);

const MACRO = 'load("@npm//:defs.bzl", "npm_link_all_packages")\n\nnpm_link_all_packages()\n';

function base() {
  inner.write("package.json", fixture("workspace_base/package.json"));
  inner.write("packages/w1/package.json", fixture("workspace_base/packages/w1/package.json"));
  inner.write("bun.lock", fixture("workspace_base/bun.lock"));
  rmSync(join(inner.dir, "packages", "w3"), { recursive: true, force: true });
}

function addW3() {
  inner.write("packages/w3/package.json", fixture("workspace_added/packages/w3/package.json"));
  inner.write("packages/w3/BUILD.bazel", MACRO);
}

const errorLine = (stderr: string) => stderr.split("\n").find((l) => l.startsWith("Error in fail:")) ?? stderr;

test(
  "a member the globs match but bun.lock lacks fails evaluation naming it",
  async () => {
    base();
    addW3();
    const result = await inner.run(["query", "//..."]);
    console.log(errorLine(result.stderr));
    expect(result.exitCode).not.toBe(0);
    expect(errorLine(result.stderr)).toContain("packages/w3");
    expect(errorLine(result.stderr)).toContain("run `bun install` and commit bun.lock");
  },
  INNER_TIMEOUT,
);

test(
  "adding and removing a member with bun.lock updated adds and removes its targets",
  async () => {
    base();
    const before = await inner.run(["query", "//..."]);
    expect(before.exitCode, before.stderr).toBe(0);
    expect(before.stdout).toContain("//packages/w1:node_modules/a");
    expect(before.stdout).not.toContain("//packages/w3");

    addW3();
    inner.write("bun.lock", fixture("workspace_added/bun.lock"));
    const added = await inner.run(["query", "//..."]);
    expect(added.exitCode, added.stderr).toBe(0);
    expect(added.stdout).toContain("//packages/w3:node_modules/c");

    base();
    const removed = await inner.run(["query", "//..."]);
    expect(removed.exitCode, removed.stderr).toBe(0);
    expect(removed.stdout).not.toContain("//packages/w3");
    expect(readFileSync(join(inner.dir, "package.json"), "utf8")).toBe(fixture("workspace_base/package.json"));
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "npm_link_all_packages() in a package that is no workspace package fails naming the valid ones",
  async () => {
    base();
    inner.write("tools/BUILD.bazel", MACRO);
    const result = await inner.run(["query", "//tools:all"]);
    rmSync(join(inner.dir, "tools"), { recursive: true, force: true });
    console.log(errorLine(result.stderr));
    expect(result.exitCode).not.toBe(0);
    for (const text of ["npm_link_all_packages", "//tools", "//packages/w1"]) expect(errorLine(result.stderr)).toContain(text);
  },
  INNER_TIMEOUT,
);

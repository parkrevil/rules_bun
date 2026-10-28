// Package executables (FR-018, US6-5, contracts/public-api.md naming rule):
// executables declared only through directories.bin get no target, and two
// bin entries whose names become one target name fail evaluation naming both.
// A bin that is a JavaScript program for Node or Bun by its #! line runs with
// the toolchain's Bun; any other fails analysis naming the reason; `bazel build
// //...` builds no bin target (feature 005 FR-012, research D1).

import { afterAll, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { rlocation } from "../support/spawn.ts";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";

const FIXTURES = "_main/bun/tests/npm/fixtures";
const archive = (p: string) => rlocation(`_main/bun/tests/npm/registry/archives/${p}.tgz`);
const inner = new Inner("bins", { npmArchives: [archive("node-bin@1.0.0"), archive("single-bin@1.0.0"), archive("dirbin@1.0.0")] });
afterAll(() => inner.close());

// A fixture file, with the loopback port of the run that wrote it replaced.
const fixture = (path: string) =>
  readFileSync(rlocation(`${FIXTURES}/${path}`), "utf8").replaceAll(/http:\/\/127\.0\.0\.1:\d+/g, inner.registry.url);

function project(name: string) {
  inner.write("package.json", fixture(`${name}/package.json`));
  inner.write("bun.lock", fixture(`${name}/bun.lock`));
}

const errorLine = (stderr: string) => stderr.split("\n").find((l) => l.startsWith("Error in fail:")) ?? stderr;

test(
  "directories.bin gives no target",
  async () => {
    project("bins_dirbin");
    const result = await inner.run(["query", "//..."]);
    expect(result.exitCode, result.stderr).toBe(0);
    expect(result.stdout).toContain("//:node_modules/dirbin\n");
    expect(result.stdout).toContain("//:node_modules/single-bin/bin/single-bin\n");
    expect(result.stdout).not.toContain("//:node_modules/dirbin/bin/");
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "two bin names that become one target name fail evaluation naming both",
  async () => {
    project("bins_clash");
    const result = await inner.run(["query", "//..."]);
    console.log(errorLine(result.stderr));
    expect(result.exitCode).not.toBe(0);
    for (const part of ["clash-bin@1.0.0", '"a b"', '"a:b"', '"a_b"']) {
      expect(errorLine(result.stderr)).toContain(part);
    }
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "FR-012: an extensionless bin whose #! line names node runs with the toolchain's Bun",
  async () => {
    project("bins_node");
    for (const bin of ["tsc", "envs", "abs", "bunbin"]) {
      const result = await inner.run(["run", `//:node_modules/node-bin/bin/${bin}`, "--", "x", "--", "y"]);
      expect(result.exitCode, result.stderr).toBe(0);
      expect(result.stdout.trim()).toBe("tsc x -- y");
    }
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "FR-012: a bin file the package repository renames is read through its safe name and runs",
  async () => {
    project("bins_node");
    const result = await inner.run(["run", "//:node_modules/node-bin/bin/build", "--", "x", "--", "y"]);
    expect(result.exitCode, result.stderr).toBe(0);
    expect(result.stdout.trim()).toBe("build x -- y");
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "FR-012: a #!/bin/sh bin fails analysis naming the reason",
  async () => {
    project("bins_node");
    const result = await inner.run(["build", "//:node_modules/node-bin/bin/sh"]);
    console.log(errorLine(result.stderr));
    expect(result.exitCode).not.toBe(0);
    expect(errorLine(result.stderr)).toContain(
      'the bin entry "sh" of the npm package node-bin@1.0.0 is the file bin/sh, which is not a JavaScript program for Node or Bun: it has none of the extensions',
    );
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "research D1: bazel build //... builds no bin target",
  async () => {
    project("bins_dirbin");
    const result = await inner.run(["build", "//..."]);
    expect(result.exitCode, result.stderr).toBe(0);
    const bin = (await inner.run(["info", "bazel-bin"])).stdout.trim();
    // single-bin/bin/single-bin is a .js file; no earlier case builds it.
    expect(existsSync(join(bin, "_npm_bin", "single-bin"))).toBe(false);
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

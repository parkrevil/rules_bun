// Package executables (FR-018, US6-5, contracts/public-api.md naming rule):
// executables declared only through directories.bin get no target, and two
// bin entries whose names become one target name fail evaluation naming both.

import { afterAll, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { rlocation } from "../support/spawn.ts";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";

const FIXTURES = "_main/bun/tests/npm/fixtures";
const inner = new Inner("bins");
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

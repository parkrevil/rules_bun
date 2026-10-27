// Packages a link reaches only through its platform select (FR-010, FR-016,
// US6): on linux x86_64, native's native-linux-x64 is unsupported (bun.lock
// records no integrity for it) and bin-darwin-arm64 (os darwin, cpu arm64) is
// absent. `bazel build //...` passes; the native link fails naming the
// unsupported package, and the bin of bin-darwin-arm64 is incompatible there
// and buildable for darwin arm64. The bin of bin-linux-x64-musl (libc musl) is
// incompatible on a Linux platform with the glibc constraint and buildable with
// the musl one (specs/004-bun-1-4-4-upgrade research R11).

import { afterAll, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { rlocation } from "../support/spawn.ts";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";

const FIXTURE = "_main/bun/tests/npm/fixtures/restricted";
const ARCHIVES = ["bin-darwin-arm64", "bin-linux-x64-musl", "native", "native-darwin-arm64", "native-darwin-x64", "native-linux-arm64", "native-linux-x64-musl", "native-win32-x64"].map(
  (p) => rlocation(`_main/bun/tests/npm/registry/archives/${p}@1.0.0.tgz`),
);
const inner = new Inner("restricted", { npmArchives: ARCHIVES });
afterAll(() => inner.close());

// A fixture file, with the loopback port of the run that wrote it replaced.
const fixture = (file: string) =>
  readFileSync(rlocation(`${FIXTURE}/${file}`), "utf8").replaceAll(/http:\/\/127\.0\.0\.1:\d+/g, inner.registry.url);
inner.write("package.json", fixture("package.json"));
inner.write("bun.lock", fixture("bun.lock"));

const build = (...args: string[]) => inner.run(["build", "--platforms=//:linux_x64", ...args]);

test(
  "bazel build //... skips the links and bins a platform select makes unusable",
  async () => {
    const result = await build("//...");
    expect(result.exitCode, result.stderr).toBe(0);
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "a link reaching an unsupported package through its select fails naming it (FR-010)",
  async () => {
    const result = await build("//:node_modules/native");
    const line = result.stderr.split("\n").find((l) => l.startsWith("Error in fail:")) ?? result.stderr;
    console.log(line);
    expect(result.exitCode).not.toBe(0);
    expect(line).toContain("native-linux-x64@1.0.0");
    expect(line).toContain("cannot be used: bun.lock records no integrity for it");
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "the bin of a platform-restricted optional package is incompatible elsewhere (FR-016)",
  async () => {
    const result = await build("//:node_modules/bin-darwin-arm64/bin/rbin");
    console.log(result.stderr.split("\n").filter((l) => /ERROR|incompatible|Error/.test(l)).join("\n"));
    expect(result.exitCode).not.toBe(0);
    expect(result.stderr).toContain("//:node_modules/bin-darwin-arm64/bin/rbin is incompatible and cannot be built");
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "the bin stays buildable on the platform its package is for (FR-016)",
  async () => {
    const result = await inner.run(["build", "--nobuild", "--platforms=//:darwin_arm64", "//:node_modules/bin-darwin-arm64/bin/rbin"]);
    expect(result.exitCode, result.stderr).toBe(0);
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "the bin of a libc-restricted optional package follows the platform's libc constraint (FR-013)",
  async () => {
    const target = "//:node_modules/bin-linux-x64-musl/bin/rbin";
    const glibc = await inner.run(["build", "--nobuild", "--platforms=//:linux_x64_glibc", target]);
    expect(glibc.exitCode).not.toBe(0);
    expect(glibc.stderr).toContain(`${target} is incompatible and cannot be built`);
    const musl = await inner.run(["build", "--nobuild", "--platforms=//:linux_x64_musl", target]);
    expect(musl.exitCode, musl.stderr).toBe(0);
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

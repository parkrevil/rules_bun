import { expect, test } from "bun:test";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { spawnTarget } from "../../support/spawn.ts";

const CWD_BUNFIG_MARKER = "RULES_BUN_CWD_BUNFIG_PRELOAD";

// A directory whose bunfig.toml preloads set.ts, which sets a global and writes a
// marker to stderr, for both `bun` and `bun test`.
function bunfigDirectory(): string {
  const dir = join(process.env.TEST_TMPDIR!, "bunfig");
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "bunfig.toml"), 'preload = ["./set.ts"]\n\n[test]\npreload = ["./set.ts"]\n');
  writeFileSync(
    join(dir, "set.ts"),
    `globalThis.__RULES_BUN_BUNFIG = "read";\nconsole.error(${JSON.stringify(CWD_BUNFIG_MARKER)});\n`,
  );
  return dir;
}

// On Linux and macOS no Bun process of the target reads $cwd/bunfig.toml, the
// first one included (FR-018a); on Windows the stub's first process may (G4).
function expectNoFirstProcessBunfig(result: { stdout: string; stderr: string }) {
  if (process.platform === "win32") {
    console.log("Not applicable on Windows: the first process may read $cwd/bunfig.toml (FR-018a, G4).");
    return;
  }
  expect(
    result.stdout + result.stderr,
    "The first Bun process, which runs the rule's launcher, read $cwd/bunfig.toml",
  ).not.toContain(CWD_BUNFIG_MARKER);
}

test("bun_binary does not read a bunfig.toml in the working directory", async () => {
  const result = await spawnTarget("_main/bun/tests/run/isolation/probe", { cwd: bunfigDirectory() });
  expect(result.exitCode).toBe(0);
  expect(JSON.parse(result.stdout).bunfig).toBeNull();
  expectNoFirstProcessBunfig(result);
});

test("bun_test does not read a bunfig.toml in the working directory", async () => {
  const result = await spawnTarget("_main/bun/tests/run/isolation/probe_test", { cwd: bunfigDirectory() });
  expect(result.exitCode, result.stderr).toBe(0);
  expectNoFirstProcessBunfig(result);
});

// A directory whose .env defines RULES_BUN_DOTENV.
function dotenvDirectory(): string {
  const dir = join(process.env.TEST_TMPDIR!, "dotenv");
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, ".env"), "RULES_BUN_DOTENV=leaked\n");
  return dir;
}

test("bun_binary does not load a .env in the working directory", async () => {
  const result = await spawnTarget("_main/bun/tests/run/isolation/probe", { cwd: dotenvDirectory() });
  expect(result.exitCode).toBe(0);
  expect(JSON.parse(result.stdout).dotenv).toBeNull();
});

test("bun_test does not load a .env in the working directory", async () => {
  const result = await spawnTarget("_main/bun/tests/run/isolation/probe_test", { cwd: dotenvDirectory() });
  expect(result.exitCode, result.stderr).toBe(0);
});

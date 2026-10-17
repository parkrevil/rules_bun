import { expect, test } from "bun:test";
import { mkdtempSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { spawnTarget } from "../../support/spawn.ts";

function piles(dir: string): number {
  return readdirSync(dir, { recursive: true }).filter((f) => String(f).endsWith(".pile")).length;
}

test("the program runs with the transpiler cache off and adds no cache file", async () => {
  const cache = mkdtempSync(join(process.env.TEST_TMPDIR!, "transpiler-cache-"));
  const env = { BUN_RUNTIME_TRANSPILER_CACHE_PATH: cache, BUN_INSPECT_CONNECT_TO: undefined };

  // On Linux and macOS the shell launcher turns the cache off for the first
  // process as well, so nothing is written. On Windows the stub cannot, and the
  // first process may cache the launcher itself (FR-018a): the count after a
  // one-line program is the baseline there.
  const tiny = await spawnTarget("_main/bun/tests/run/isolation/tiny", { env });
  expect(tiny.exitCode).toBe(0);
  const baseline = piles(cache);
  if (process.platform !== "win32") expect(baseline).toBe(0);

  const probe = await spawnTarget("_main/bun/tests/run/isolation/cache_probe", { env });
  expect(probe.exitCode).toBe(0);
  expect(probe.stdout.trim()).toBe("0");
  expect(piles(cache)).toBe(baseline);
});

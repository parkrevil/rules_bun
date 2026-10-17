import { expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { spawnTarget, testCaseNames } from "../../../support/spawn.ts";

const TARGET = "_main/bun/tests/run/protocol/shard/shard_target_test";
const ALL = ["a one", "a two", "b one", "b two", "c one", "c two"];

async function runShard(total: number, index: number, label: string, filter?: string) {
  const dir = process.env.TEST_TMPDIR!;
  const report = join(dir, `${label}-${index}.xml`);
  const status = join(dir, `${label}-${index}.status`);
  const result = await spawnTarget(TARGET, {
    env: {
      TEST_TOTAL_SHARDS: String(total),
      TEST_SHARD_INDEX: String(index),
      TEST_SHARD_STATUS_FILE: status,
      XML_OUTPUT_FILE: report,
      TESTBRIDGE_TEST_ONLY: filter,
    },
  });
  return { ...result, ran: testCaseNames(report), status: existsSync(status) };
}

test("two shards together run every test exactly once", async () => {
  const first = await runShard(2, 0, "two");
  const second = await runShard(2, 1, "two");
  expect(first.exitCode).toBe(0);
  expect(second.exitCode).toBe(0);
  expect([...first.ran, ...second.ran].sort()).toEqual(ALL);
  expect(first.status).toBe(true);
  expect(second.status).toBe(true);
});

test("a shard that gets no file passes", async () => {
  const runs = [];
  for (let index = 0; index < 4; index++) runs.push(await runShard(4, index, "four"));
  const empty = runs.filter((r) => r.ran.length === 0);
  expect(empty.length).toBe(1);
  expect(empty[0].exitCode).toBe(0);
  expect(runs.flatMap((r) => r.ran).sort()).toEqual(ALL);
});

for (const index of [0, 1]) {
  test(`filtering shard ${index} of a sharded bun_test fails with an English error`, async () => {
    const result = await runShard(2, index, "filtered", "a one");
    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain("filtering a sharded bun_test is not supported");
    expect(result.ran).toEqual([]);
    expect(result.status).toBe(false);
  });
}

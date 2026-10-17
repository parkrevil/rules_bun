import { expect, test } from "bun:test";
import { spawnTarget } from "../../../support/spawn.ts";

const TARGET = "_main/bun/tests/run/protocol/allowlist/target_test";

const ALLOWED = [
  "--timeout=5000",
  "--rerun-each=1",
  "--retry=0",
  "--concurrent",
  "--randomize",
  "--seed=1",
  "--bail",
  "--bail=1",
  "--max-concurrency=2",
  "--todo",
  "--isolate",
  "--smol",
  "--conditions=x",
  "--prefer-offline",
  "--frozen-lockfile",
];

const REJECTED = [
  "x.test.ts",
  "--",
  "-talpha",
  "-uts",
  "-r./x.ts",
  "--path-ignore-patterns=x",
  "--changed",
  "--test-name-pattern=x",
  "--reporter=junit",
  "--dots",
  "--coverage",
  "--shard=1/1",
  "-u",
  "--update-snapshots",
  "--env-file=x",
  "--preload=x",
  "--config=x",
  "--parallel",
  "--no-isolate",
  "--watch",
  "--inspect",
  "--define=a:b",
  "--loader=.js:text",
  "--tsconfig-override=x",
  "--timings",
];

for (const arg of ALLOWED) {
  test(`allowed argument ${arg} is accepted`, async () => {
    const result = await spawnTarget(TARGET, { args: [arg] });
    expect(result.stderr).not.toContain("is not allowed");
    expect(result.exitCode).toBe(0);
  });
}

for (const arg of REJECTED) {
  test(`argument ${arg} is rejected with an English error naming it`, async () => {
    const result = await spawnTarget(TARGET, { args: [arg] });
    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain(`bun_test argument ${JSON.stringify(arg)} is not allowed`);
  });
}

import { test } from "bun:test";

// Longer than Bun's default timeout of 5000 ms: passes only when the declared
// `--timeout=6000` reaches `bun test`.
test("takes 5500 ms", async () => {
  await Bun.sleep(5500);
});

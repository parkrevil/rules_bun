import { test } from "bun:test";

test("takes 200 ms", async () => {
  await Bun.sleep(200);
});

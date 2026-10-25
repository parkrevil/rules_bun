import { expect, test } from "bun:test";
import a from "a";

test("a loads and no bunfig.toml or .env of the working directory took effect", () => {
  expect(a.version).toBe("1.0.0");
  expect((globalThis as Record<string, unknown>).__RULES_BUN_BUNFIG).toBeUndefined();
  expect(process.env.RULES_BUN_DOTENV).toBeUndefined();
});

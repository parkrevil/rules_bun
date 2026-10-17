import { expect, test } from "bun:test";
import { greet } from "./greet.ts";

test("greet names the person", () => {
  expect(greet("world")).toBe("hello, world");
});

test("the module root's bunfig.toml and .env, declared by no target, take no effect", () => {
  expect(
    (globalThis as Record<string, unknown>).__RULES_BUN_SMOKE_PRELOAD,
    "Bun read the bunfig.toml at the root of e2e/smoke",
  ).toBeUndefined();
  expect(process.env.RULES_BUN_SMOKE_DOTENV, "Bun loaded the .env at the root of e2e/smoke").toBeUndefined();
});

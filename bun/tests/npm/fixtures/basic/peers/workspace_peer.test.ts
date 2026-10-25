// US5-2: p-user depends on p but provides none of p's peers.

import { expect, test } from "bun:test";
import p from "p-user";

test("a non-optional peer the dependent does not provide is the workspace's version", () => {
  expect(p.q).toBe("1.0.0");
});

test("an optional peer the dependent does not provide cannot load", () => {
  expect(p.r).toBeNull();
  expect(p.rError).toContain("Cannot find module 'r'");
});

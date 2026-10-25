// The root workspace package of the fixture (US4-3, alias Edge Case).

import { expect, test } from "bun:test";
import aliased from "aliased";
import q from "q";

test("the root gets q@1.0.0 from the catalog", () => {
  expect(q).toEqual({ name: "q", version: "1.0.0" });
});

test("an npm: alias loads the package it names", () => {
  expect(aliased).toEqual({ name: "b", version: "2.0.0" });
});

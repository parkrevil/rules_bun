// US5-1: a peer the dependent provides is one instance for the package and the
// dependent.

import { expect, test } from "bun:test";
import identA from "ident-a";
import state from "state";

test("ident-a loads the state instance the test imports", () => {
  expect(state.version).toBe("1.0.0");
  expect(identA.state).toBe(state);
});

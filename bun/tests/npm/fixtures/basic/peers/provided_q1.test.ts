// US5-3: through the root's dependency p, p's peer q is the root's q@1.0.0.

import { expect, test } from "bun:test";
import p from "p";

test("p loads the q@1.0.0 its dependent provides", () => {
  expect(p.q).toBe("1.0.0");
});

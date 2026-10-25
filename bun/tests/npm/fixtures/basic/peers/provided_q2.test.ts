// US5-3: through q2-user, which depends on q@2.0.0, p's peer q is q@2.0.0.

import { expect, test } from "bun:test";
import p from "q2-user";

test("p loads the q@2.0.0 its dependent provides", () => {
  expect(p.q).toBe("2.0.0");
});

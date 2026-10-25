// The workspace member w1 (US4-1, US4-2, US4-3, US4-6): its packages at the
// versions bun.lock lists for it, and the member w2 by package name.

import { expect, test } from "bun:test";
import a from "a";
import q from "q";
import singleBin from "single-bin/package.json";
import state from "state";
import w2 from "w2";

test("w1 imports a, which it declares", () => {
  expect(a).toEqual({ name: "a", version: "1.0.0", b: "1.0.0" });
});

test("w1 gets q@2.0.0 while the root gets q@1.0.0", () => {
  expect(q).toEqual({ name: "q", version: "2.0.0" });
});

test("w1 imports the member w2 by package name and gets its sources", () => {
  expect(w2).toEqual({ name: "w2", c: { name: "c", version: "1.0.0", b: "2.0.0" } });
});

test("a devDependency and a peerDependency load at the lockfile's versions", () => {
  expect(singleBin.version).toBe("1.0.0");
  expect(state.version).toBe("1.0.0");
});

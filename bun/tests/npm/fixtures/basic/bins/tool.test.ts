// US6-2: single-bin ran as the tool of a run_binary action and wrote its
// arguments into the action's output.

import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";

test("the tool wrote its arguments", () => {
  expect(JSON.parse(readFileSync(`${import.meta.dir}/written.json`, "utf8"))).toEqual(["from", "run_binary"]);
});

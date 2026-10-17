import { test } from "bun:test";

console.log("TEST_FILE_RAN");

test("runs", () => {
  console.log("TEST_BODY_RAN");
});

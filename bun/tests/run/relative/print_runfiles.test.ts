import { test } from "bun:test";

test("prints the runfiles variables", () => {
  console.log(
    `RUNFILES ${JSON.stringify({ dir: process.env.RUNFILES_DIR, manifest: process.env.RUNFILES_MANIFEST_FILE })}`,
  );
});

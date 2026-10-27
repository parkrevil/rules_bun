// Canary C13 (FR-028): pins that Bun 1.4.4 compiles a regular expression of
// 1,048,576 pattern characters, accepts it as a Bun.plugin onLoad filter, and
// rejects one of 1,048,577 characters as too large. When this fails, revisit the
// prefix trie and the declared-file limit of the load guard (R13), which the fix
// of oven-sh/bun PR #36757 would remove.

import { test } from "bun:test";

const LIMIT = 1048576;
const MESSAGE =
  "Bun's regular-expression size limit changed: revisit the prefix trie and the declared-file limit (R13); " +
  "https://github.com/oven-sh/bun/pull/36757";

test("the longest guard pattern compiles and one character more does not", () => {
  let observed: string;
  try {
    const filter = new RegExp("a".repeat(LIMIT));
    Bun.plugin({
      name: "c13 canary",
      setup(build) {
        build.onLoad({ filter, namespace: "c13" }, () => ({ contents: "", loader: "js" }));
      },
    });
    observed = "the pattern of 1,048,576 characters compiled and Bun.plugin accepted it";
  } catch (error) {
    throw new Error(`${MESSAGE}; the pattern of 1,048,576 characters failed: ${error}`);
  }
  try {
    new RegExp("a".repeat(LIMIT + 1));
  } catch (error) {
    if (String(error).includes("regular expression too large")) return;
    throw new Error(`${MESSAGE}; ${observed}, and the pattern of 1,048,577 characters failed with ${error}`);
  }
  throw new Error(`${MESSAGE}; ${observed}, and the pattern of 1,048,577 characters compiled`);
});

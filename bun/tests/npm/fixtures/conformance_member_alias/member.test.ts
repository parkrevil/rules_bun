// BC-4 (feature 006): a registry package's dependency on a workspace member links to the member,
// as the pinned Bun links it, when the target declares the member's target through an alias (T146).

import { expect, test } from "bun:test";
import user from "member-user";

test("member-user loads the workspace member member-lib", () => {
  expect(user.lib.name).toBe("member-lib");
});

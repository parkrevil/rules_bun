// BC-11 (feature 006): react-dom@19.2.0 binds its peer react, so its store directory in the copy
// tree carries a peer hash, as the pinned Bun's isolated store names every entry with peer
// bindings; react, without peers, has none.

import { expect, test } from "bun:test";
import { realpathSync } from "node:fs";

const posix = (path: string) => realpathSync(path).replaceAll("\\", "/");

test("react-dom's store directory carries a peer hash, react's none", () => {
  expect(posix(require.resolve("react-dom"))).toMatch(/\/\.store\/react-dom@19\.2\.0\+[0-9a-f]{16}\/node_modules\/react-dom\//);
  expect(posix(require.resolve("react"))).toContain("/.store/react@19.2.0/node_modules/react/");
});

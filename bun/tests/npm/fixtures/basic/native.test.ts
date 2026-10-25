import { expect, test } from "bun:test";
import native from "native";

// The package native's entry tries first for this platform (US3-1).
const EXPECTED: Record<string, string> = {
  "darwin-arm64": "native-darwin-arm64",
  "darwin-x64": "native-darwin-x64",
  "linux-arm64": "native-linux-arm64",
  "linux-x64": "native-linux-x64",
  "win32-x64": "native-win32-x64",
};

test("native loads the platform package of this platform", () => {
  expect(native).toBe(EXPECTED[`${process.platform}-${process.arch}`]);
});

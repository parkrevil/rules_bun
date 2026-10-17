// Imports the case named by the first argument, without try/catch, so a module
// the guard rejects fails the run.
import { rlocation } from "../../support/spawn.ts";

const name = process.argv[2];
switch (name) {
  case "declared":
    await import("./declared_esm.ts");
    require("./declared_cjs.cjs");
    await import("./declared.json");
    break;
  case "stale":
    await import("./stale.ts");
    break;
  case "climb":
    await import("../../../../../../climb.ts");
    break;
  case "imports":
    await import("#undeclared");
    break;
  case "node_modules":
    await import("undeclared-pkg");
    break;
  case "cjs":
    require("./undeclared.cjs");
    break;
  case "json":
    await import("./undeclared.json");
    break;
  case "newline": {
    // A path with line terminators, written outside the tree at run time.
    const { mkdtempSync, writeFileSync } = require("node:fs");
    const { join } = require("node:path");
    const { tmpdir } = require("node:os");
    // Windows forbids characters 1-31 in file names, so only U+2028 is used there.
    const name = process.platform === "win32" ? "line\u2028break.ts" : "line\nbreak\r\u2028.ts";
    const file = join(mkdtempSync(join(tmpdir(), "rules_bun-guard-")), name);
    writeFileSync(file, 'export const newline = "newline";\n');
    await import(file);
    break;
  }
  case "original":
    await import(rlocation("_main/bun/tests/run/guard/declared.json"));
    break;
  default:
    throw new Error(`unknown case ${name}`);
}
console.log(`imported ${name}`);

// Canary C18 (FR-009, FR-013): pins that the toolchain's Bun runs a file without
// a source extension whose first line is `#!/usr/bin/env node`, as CommonJS
// (typescript's bin/tsc) and as an ES module, when given its absolute path as
// the launcher gives it. rules_bun runs such an npm bin with Bun (FR-012,
// bun/private/npm_repositories.bzl); bun.com documents that an absolute path
// runs as a source file, not which loader a file without an extension gets.

import { expect, test } from "bun:test";
import { mkdtempSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const MESSAGE = "rules_bun runs an npm bin file without a source extension with Bun (FR-012, bun/private/npm_repositories.bzl)";

// RULES_BUN_CANARY_RED=1 alters the expectation, so the canary is seen failing
// (the convention of bun/tests/canary/npm/support.ts).
const expected = process.env.RULES_BUN_CANARY_RED ? '["altered"]' : '["a"]';

const cases: [string, Record<string, string>][] = [
  [
    "CommonJS",
    {
      tsc: '#!/usr/bin/env node\nrequire("./lib.js");\n',
      "lib.js": "console.log(JSON.stringify(process.argv.slice(2)));\n",
    },
  ],
  [
    "ES module",
    {
      tsc: '#!/usr/bin/env node\nimport "./lib.mjs";\n',
      "lib.mjs": "console.log(JSON.stringify(process.argv.slice(2)));\n",
    },
  ],
];

for (const [kind, files] of cases) {
  test(`an extensionless ${kind} file after #!/usr/bin/env node runs`, () => {
    const dir = mkdtempSync(join(process.env.TEST_TMPDIR!, "c18-"));
    for (const [name, text] of Object.entries(files)) writeFileSync(join(dir, name), text);
    const result = Bun.spawnSync([process.execPath, "--no-env-file", "--no-install", join(dir, "tsc"), "a"], { cwd: dir });
    const observed = {
      stdout: result.stdout.toString().trim(),
      stderr: result.stderr.toString(),
      exitCode: result.exitCode,
    };
    expect(observed, `${MESSAGE}; observed ${JSON.stringify(observed)}`).toEqual({ stdout: expected, stderr: "", exitCode: 0 });
  });
}

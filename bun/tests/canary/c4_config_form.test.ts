// Canary C4 (FR-028): pins that the runtime command `bun --config <path> <file>`
// and `bun -c <path> <file>` run <path> as the entry point instead of reading it
// as the configuration (hermeticbuild/hermetic-launcher#81). When this fails,
// revisit the Windows first-process limitation (FR-018a, G4) and the MODULE.bazel
// comment on hermetic_launcher (G14).

import { test } from "bun:test";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const MESSAGE =
  "Bun now reads a configuration file given as a separate argument: revisit the Windows first-process limitation " +
  "(FR-018a, G4); hermetic-launcher's side is the MODULE.bazel comment (G14); " +
  "https://github.com/hermeticbuild/hermetic-launcher/issues/81";

for (const option of ["--config", "-c"]) {
  test(`bun ${option} <path> <file> runs neither the configuration's preload nor <file>`, () => {
    const root = join(process.env.TEST_TMPDIR!, `c4${option}`);
    mkdirSync(root, { recursive: true });
    writeFileSync(join(root, "marker.ts"), 'console.log("CONFIG_PRELOAD");\n');
    writeFileSync(join(root, "main.ts"), 'console.log("MAIN");\n');
    writeFileSync(join(root, "config.toml"), 'preload = ["./marker.ts"]\n');

    const result = Bun.spawnSync([process.execPath, option, join(root, "config.toml"), "main.ts"], { cwd: root });
    const output = result.stdout.toString() + result.stderr.toString();
    if (output.includes("CONFIG_PRELOAD") || output.includes("MAIN")) {
      throw new Error(`${MESSAGE}; observed output ${JSON.stringify(output)}, exit ${result.exitCode}`);
    }
  });
}

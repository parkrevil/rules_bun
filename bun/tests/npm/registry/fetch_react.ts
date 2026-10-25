// Writes the root JSX proof's fixture project bun/tests/npm/fixtures/jsx/
// (research R14, G3). Run by hand, with network, with the pinned Bun from the
// repository root:
//
//   $(bazel info output_base)/external/+bun+bun_linux-x64/bun bun/tests/npm/registry/fetch_react.ts
//
// It downloads react, react-dom and scheduler from https://registry.npmjs.org,
// verifies each archive against the integrity its packument publishes, writes
// them to bun/tests/npm/fixtures/jsx/archives/, and runs the pinned Bun's
// `install` against the public registry to write bun.lock. It then checks that
// bun.lock records the same three integrities. e2e/smoke pins the same versions.

import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { integrity } from "../../support/npm_registry.ts";

const REGISTRY = "https://registry.npmjs.org";
const PACKAGES: [string, string][] = [
  ["react", "19.2.0"],
  ["react-dom", "19.2.0"],
  ["scheduler", "0.27.0"],
];

const project = join(import.meta.dir, "..", "fixtures", "jsx");
const archives = join(project, "archives");
mkdirSync(archives, { recursive: true });

const manifest = {
  name: "jsx",
  private: true,
  dependencies: { react: "19.2.0", "react-dom": "19.2.0" },
};
writeFileSync(join(project, "package.json"), JSON.stringify(manifest, null, 2) + "\n");

const published: Record<string, string> = {};
for (const [name, version] of PACKAGES) {
  const packument = await (await fetch(`${REGISTRY}/${name}/${version}`)).json();
  const expected: string = packument.dist.integrity;
  const bytes = new Uint8Array(await (await fetch(packument.dist.tarball)).arrayBuffer());
  const algorithm = expected.slice(0, expected.indexOf("-")) as "sha512";
  if (integrity(bytes, algorithm) !== expected) {
    throw new Error(`${name}@${version}: the archive does not match the published integrity ${expected}`);
  }
  writeFileSync(join(archives, `${name}-${version}.tgz`), bytes);
  published[`${name}@${version}`] = expected;
  console.log(`${name}@${version} ${expected}`);
}

const work = mkdtempSync(join(tmpdir(), "rules-bun-jsx-"));
try {
  writeFileSync(join(work, "package.json"), JSON.stringify(manifest, null, 2) + "\n");
  const child = Bun.spawn([process.execPath, "install", `--registry=${REGISTRY}`], {
    cwd: work,
    env: { ...process.env, BUN_INSTALL_CACHE_DIR: join(work, ".cache"), NO_COLOR: "1" },
    stdout: "inherit",
    stderr: "inherit",
  });
  if ((await child.exited) !== 0) throw new Error("bun install failed");
  const text = readFileSync(join(work, "bun.lock"), "utf8");
  const lock = Bun.JSONC.parse(text) as { packages: Record<string, any[]> };
  for (const entry of Object.values(lock.packages)) {
    const expected = published[entry[0]];
    if (expected === undefined) throw new Error(`bun.lock lists ${entry[0]}, which this script did not fetch`);
    if (entry[3] !== expected) throw new Error(`bun.lock records ${entry[3]} for ${entry[0]}, not ${expected}`);
  }
  writeFileSync(join(project, "bun.lock"), text);
  console.log("bun.lock records the three published integrities");
} finally {
  rmSync(work, { recursive: true, force: true });
}

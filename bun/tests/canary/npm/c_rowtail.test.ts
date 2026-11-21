// Canary C-ROWTAIL (feature 006, research Part 4 L36, L37): the slots after the info object of a
// row that is not an npm version. For a GitHub dependency the pinned Bun writes
// ["<name>@github:<owner>/<repo>#<commit>", {info}, "<tag>", "<integrity>"] (LOCK writer L860–L894,
// shared with `git+` rows): slot 2 is the `.bun-tag`, the root folder of GitHub's tarball
// (`<owner>-<repo>-<commit>`, repository.rs L125–L130), and slot 3 the tarball's integrity; for a
// tarball URL it writes ["<name>@<url>", {info}, "<integrity>"] (L799–L818). A frozen install loads
// both rows (LOCK L2671–L2735). load_lockfile in bun/private/bun_lockfile.bzl reads these slots only
// to refuse what Bun refuses (T147), so each must stay in the form Bun accepts. GITHUB_API_URL
// points Bun's GitHub download at the loopback registry, which serves the tarball.

import { test } from "bun:test";
import { readFileSync } from "node:fs";
import { integrity } from "../../support/npm_registry.ts";
import { rlocation } from "../../support/spawn.ts";
import { writeTgz } from "../../support/tar.ts";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const READER = "load_lockfile in bun/private/bun_lockfile.bzl";
const COMMIT = "0123456789abcdef0123456789abcdef01234567";
const TAG = "o-r-0123456";

// What `Repository::is_safe_resolved_tag` accepts (repository.rs L114–L123).
const SAFE_TAG = /^(?!-)(?!\.{1,2}$)[A-Za-z0-9_.-]{1,256}$/;

const tarball = writeTgz([
  { name: `${TAG}/package.json`, type: "file", data: new TextEncoder().encode(manifest({ name: "r", version: "1.0.0" })) },
]);
const archive = readFileSync(rlocation("_main/bun/tests/npm/registry/archives/a@1.0.0.tgz"));

function files(url: string) {
  return {
    "package.json": manifest({ name: "c-rowtail", dependencies: { r: `github:o/r#${COMMIT}`, tb: `${url}/a/-/a-1.0.0.tgz` } }),
  };
}

function options(port?: number) {
  return {
    registry: { files: { [`/repos/o/r/tarball/${COMMIT}`]: tarball }, port },
    env: (url: string) => ({ GITHUB_API_URL: url }),
  };
}

test("a GitHub row's tag and integrity and a tarball row's integrity are written as Bun loads them", async () => {
  const first = await runInstall(files, options());
  // The tarball row holds the first run's URL, so the frozen run serves on the same port.
  const project = { "package.json": readFileSync(`${first.dir}/package.json`, "utf8"), "bun.lock": first.text };
  let lock: Record<string, any>;
  try {
    ({ lock } = await runInstall(project, {
      ...options(Number(new URL(first.url).port)),
      dir: first.dir,
      frozenLockfile: true,
      // Red: slot 2 of the GitHub row is no tag Bun accepts.
      alter: red({ lockfile: (text) => text.replace(`"${TAG}"`, '"o/r"') }),
    }));
  } catch (error) {
    canaryFail("C-ROWTAIL", "rows after the info object", READER, LOCKFILE_SOURCE, String(error));
  }
  const github = lock.packages.r;
  if (!Array.isArray(github) || github.length !== 4 || github[2] !== TAG || !SAFE_TAG.test(github[2])) {
    canaryFail("C-ROWTAIL", "GitHub row slot 2", READER, LOCKFILE_SOURCE, github);
  }
  if (github[3] !== integrity(tarball, "sha512")) {
    canaryFail("C-ROWTAIL", "GitHub row slot 3", READER, LOCKFILE_SOURCE, github);
  }
  const tb = lock.packages.tb;
  if (!Array.isArray(tb) || tb.length !== 3 || tb[2] !== integrity(archive, "sha512")) {
    canaryFail("C-ROWTAIL", "tarball row slot 2", READER, LOCKFILE_SOURCE, tb);
  }
});

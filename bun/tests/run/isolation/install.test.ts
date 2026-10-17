import { afterAll, beforeAll, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { rlocation, spawnTarget } from "../../support/spawn.ts";

// A local npm registry serving rules-bun-fixture-pkg 1.0.0 (the checked-in
// tarball, made with `bun pm pack` in registry/rules-bun-fixture-pkg).
const NAME = "rules-bun-fixture-pkg";
const TARBALL = readFileSync(rlocation(`_main/bun/tests/run/isolation/registry/${NAME}-1.0.0.tgz`));
const INTEGRITY = `sha512-${new Bun.CryptoHasher("sha512").update(TARBALL).digest("base64")}`;

let server: ReturnType<typeof Bun.serve>;

beforeAll(() => {
  server = Bun.serve({
    port: 0,
    fetch(request) {
      const path = new URL(request.url).pathname;
      if (path === `/${NAME}`) {
        return Response.json({
          name: NAME,
          "dist-tags": { latest: "1.0.0" },
          versions: {
            "1.0.0": {
              name: NAME,
              version: "1.0.0",
              main: "index.js",
              dist: { tarball: `${server.url}${NAME}/-/${NAME}-1.0.0.tgz`, integrity: INTEGRITY },
            },
          },
        });
      }
      if (path === `/${NAME}/-/${NAME}-1.0.0.tgz`) return new Response(TARBALL);
      return new Response("not found", { status: 404 });
    },
  });
});

afterAll(() => server.stop(true));

for (const target of ["imports_package", "imports_package_test"]) {
  test(`${target} does not install a missing package`, async () => {
    const root = mkdtempSync(join(process.env.TEST_TMPDIR!, `${target}-`));
    const cache = join(root, "cache");
    const cwd = join(root, "cwd");
    mkdirSync(cache);
    mkdirSync(cwd);
    const result = await spawnTarget(`_main/bun/tests/run/isolation/${target}`, {
      cwd,
      env: { BUN_CONFIG_REGISTRY: server.url.href, BUN_INSTALL_CACHE_DIR: cache },
    });
    expect(result.exitCode).not.toBe(0);
    expect(result.stdout + result.stderr).toMatch(new RegExp(`Cannot find (?:module|package) ['"]${NAME}['"]`));
    expect(readdirSync(cache)).toEqual([]);
  });
}

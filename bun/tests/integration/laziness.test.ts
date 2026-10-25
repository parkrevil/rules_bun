// Packages are fetched only when a target needs them (US2-3, SC-005): from a
// fresh output base and an empty repository cache, a target needing no package
// requests no archive, one needing a requests only a and b@1.0.0, and x, whose
// archive the server does not have, leaves the build and test green. A target
// needing p-user requests only p-user, p and p's resolved peer q@1.0.0: neither
// the optional peer r, which p-user does not provide, nor q@2.0.0, which the
// lockfile lists for q2-user (the server has neither).

import { afterAll, expect, test } from "bun:test";
import { rlocation } from "../support/spawn.ts";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";

const archive = (p: string) => rlocation(`_main/bun/tests/npm/registry/archives/${p}.tgz`);

const inner = new Inner("fetch", {
  npmArchives: ["a@1.0.0", "b@1.0.0", "b@2.0.0", "c@1.0.0", "p@1.0.0", "p-user@1.0.0", "q@1.0.0"].map(archive),
});
afterAll(() => inner.close());

const archiveRequests = () => inner.log.filter((e) => e.path.endsWith(".tgz")).map((e) => e.path);

test(
  "lazy fetching",
  async () => {
    expect(inner.repositoryCacheWasEmpty).toBe(true);

    const plain = await inner.run(["build", "//:plain_test"]);
    expect(plain.exitCode, plain.stderr).toBe(0);
    expect(archiveRequests()).toEqual([]);

    const a = await inner.run(["build", "//:a_test"]);
    expect(a.exitCode, a.stderr).toBe(0);
    expect(archiveRequests().sort()).toEqual(["/a/-/a-1.0.0.tgz", "/b/-/b-1.0.0.tgz"]);

    const tests = await inner.run(["test", "//:plain_test", "//:a_test", "--test_output=errors"]);
    expect(tests.exitCode, tests.stdout + tests.stderr).toBe(0);
    expect(archiveRequests().sort()).toEqual(["/a/-/a-1.0.0.tgz", "/b/-/b-1.0.0.tgz"]);
    expect(inner.log.some((e) => e.path.includes("/x/"))).toBe(false);

    const peers = await inner.run(["test", "//:p_user_test", "--test_output=errors"]);
    expect(peers.exitCode, peers.stdout + peers.stderr).toBe(0);
    expect(archiveRequests().sort()).toEqual([
      "/a/-/a-1.0.0.tgz",
      "/b/-/b-1.0.0.tgz",
      "/p-user/-/p-user-1.0.0.tgz",
      "/p/-/p-1.0.0.tgz",
      "/q/-/q-1.0.0.tgz",
    ]);
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

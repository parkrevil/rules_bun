// Registries and credentials through Bazel's downloader (FR-009, FR-019, FR-020,
// research R3, R11): a full lockfile URL is requested where it points (US7-1); a
// scope the passed .npmrc maps to a registry is requested there (US7-6); a
// .netrc in the home directory supplies a registry's credential (US7-4);
// authentication values in an .npmrc are not used (US7-7). No secret appears
// in a generated file or in `bazel mod show_repo`.

import { afterAll, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { type Credential, type Registry, startRegistry } from "../support/npm_registry.ts";
import { rlocation } from "../support/spawn.ts";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";
import { findSecrets } from "./support/secrets.ts";

const archive = (p: string) => rlocation(`_main/bun/tests/npm/registry/archives/${p}.tgz`);
const ARCHIVES = [archive("@scope+s@1.0.0"), archive("a@1.0.0"), archive("b@1.0.0")];
const SECRETS = ["SECRET-NETRC", "SECRET-NPMRC", "SECRET-HOME-NPMRC"];
const CREDENTIAL: Credential = { basic: ["rules-bun-user", "SECRET-NETRC"] };

const cleanups: (() => Promise<void> | void)[] = [];
afterAll(async () => {
  for (const cleanup of cleanups) await cleanup();
});

// The committed lockfile the pinned Bun 1.4.4 wrote for package.json
// (workspaces/registries/bun.lock, which the conformance test compares with the
// pinned Bun's install, feature 006 T143), with the URL of each entry as the case
// gives it; nothing else changes.
function lockfile({ inner, committed }: Setup, urls: { a: string; s: string; b: string }): string {
  let text = committed;
  const rows: [string, string][] = [["@scope/s", urls.s], ["a", urls.a], ["b", urls.b]];
  for (const [name, url] of rows) {
    const from = `"${tarball(inner.registry.url, name, "1.0.0")}"`;
    if (!text.includes(from)) throw new Error(`workspaces/registries/bun.lock holds no ${from}`);
    text = text.replace(from, `"${url}"`);
  }
  return text;
}

interface Setup {
  inner: Inner;
  second: Registry;
  /** The committed bun.lock as the session assembled it. */
  committed: string;
}

// An inner workspace with the main loopback server and a second one on another
// port; `home` files go into the inner Bazel's HOME.
function setup(credential: Credential | undefined, home: Record<string, string>): Setup {
  const second = startRegistry({ archives: ARCHIVES, credential });
  const homeDir = mkdtempSync(join(process.env.TEST_TMPDIR!, "h"));
  for (const [name, text] of Object.entries(home)) writeFileSync(join(homeDir, name), text);
  const inner = new Inner("registries", { npmArchives: ARCHIVES, env: { HOME: homeDir, USERPROFILE: homeDir, NETRC: undefined } });
  cleanups.push(() => inner.close(), () => second.stop());
  return { inner, second, committed: readFileSync(join(inner.dir, "bun.lock"), "utf8") };
}

const tarball = (registry: string, name: string, version: string) =>
  `${registry}/${name}/-/${name.split("/").pop()}-${version}.tgz`;

async function assertNoSecret(inner: Inner) {
  expect(await findSecrets(inner, SECRETS, ["npm", "npm__a__1.0.0", "npm___scope_s__1.0.0"])).toEqual([]);
}

const requested = (registry: Registry, path: string) =>
  registry.log.filter((e) => e.path === path).map((e) => e.status);

test(
  "US7-1: a full URL in bun.lock is requested there",
  async () => {
    const session = setup(undefined, {});
    const { inner, second } = session;
    const main = inner.registry.url;
    inner.write(".npmrc", "");
    inner.write("bun.lock", lockfile(session, { a: tarball(second.url, "a", "1.0.0"), s: tarball(main, "@scope/s", "1.0.0"), b: tarball(main, "b", "1.0.0") }));
    const result = await inner.run(["build", "//:node_modules/a"]);
    expect(result.exitCode, result.stderr).toBe(0);
    expect(requested(second, "/a/-/a-1.0.0.tgz")).toEqual([200]);
    expect(requested(inner.registry, "/a/-/a-1.0.0.tgz")).toEqual([]);
    await assertNoSecret(inner);
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "US7-6: a scope the passed .npmrc maps is requested from that registry",
  async () => {
    const session = setup(undefined, {});
    const { inner, second } = session;
    const main = inner.registry.url;
    inner.write(".npmrc", `@scope:registry=${second.url}/\n`);
    inner.write("bun.lock", lockfile(session, { a: tarball(main, "a", "1.0.0"), s: "", b: tarball(main, "b", "1.0.0") }));
    const result = await inner.run(["build", "//:node_modules/@scope/s"]);
    expect(result.exitCode, result.stderr).toBe(0);
    expect(requested(second, "/@scope/s/-/s-1.0.0.tgz")).toEqual([200]);
    await assertNoSecret(inner);
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "US7-4: a .netrc in the home directory supplies the registry's credential",
  async () => {
    const session = setup(CREDENTIAL, {
      ".netrc": "machine 127.0.0.1\nlogin rules-bun-user\npassword SECRET-NETRC\n",
    });
    const { inner, second } = session;
    const main = inner.registry.url;
    inner.write(".npmrc", "");
    inner.write("bun.lock", lockfile(session, { a: tarball(second.url, "a", "1.0.0"), s: tarball(main, "@scope/s", "1.0.0"), b: tarball(main, "b", "1.0.0") }));
    const result = await inner.run(["build", "//:node_modules/a"]);
    console.log(result.stderr.split("\n").filter((l) => /ERROR|Error/.test(l)).join("\n"));
    expect(result.exitCode, result.stderr).toBe(0);
    expect(requested(second, "/a/-/a-1.0.0.tgz")).toContain(200);
    await assertNoSecret(inner);
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "US7-7: authentication values in an .npmrc are not used",
  async () => {
    const session = setup(CREDENTIAL, { ".npmrc": "_authToken=SECRET-HOME-NPMRC\n" });
    const { inner, second } = session;
    const main = inner.registry.url;
    const host = second.url.replace(/^http:/, "");
    inner.write(".npmrc", `${host}/:_authToken=SECRET-NPMRC\n_auth=${btoa("rules-bun-user:SECRET-NPMRC")}\n`);
    inner.write("bun.lock", lockfile(session, { a: tarball(second.url, "a", "1.0.0"), s: tarball(main, "@scope/s", "1.0.0"), b: tarball(main, "b", "1.0.0") }));
    const result = await inner.run(["build", "//:node_modules/a"]);
    console.log(result.stderr.split("\n").filter((l) => /ERROR|Error/.test(l)).join("\n"));
    expect(result.exitCode).not.toBe(0);
    expect(result.stderr).toContain(tarball(second.url, "a", "1.0.0"));
    expect(requested(second, "/a/-/a-1.0.0.tgz")).not.toContain(200);
    await assertNoSecret(inner);
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

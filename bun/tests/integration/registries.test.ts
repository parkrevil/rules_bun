// Registries and credentials through Bazel's downloader (FR-009, FR-019, FR-020,
// research R3, R11): a full lockfile URL is requested where it points (US7-1); a
// scope the passed .npmrc maps to a registry is requested there (US7-6); a
// .netrc in the home directory supplies a registry's credential (US7-4);
// authentication values in an .npmrc are not used (US7-7). No secret appears
// in a generated file or in `bazel mod show_repo`.

import { afterAll, expect, test } from "bun:test";
import { mkdtempSync, writeFileSync } from "node:fs";
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

// The lockfile the pinned Bun 1.4.2 wrote for package.json, with the URL of
// each entry as the case gives it.
function lockfile(urls: { a: string; s: string; b: string }): string {
  return `{
  "lockfileVersion": 2,
  "configVersion": 1,
  "workspaces": {
    "": {
      "name": "registries",
      "dependencies": {
        "@scope/s": "1.0.0",
        "a": "1.0.0",
      },
    },
  },
  "packages": {
    "@scope/s": ["@scope/s@1.0.0", "${urls.s}", { "bin": { "s-tool": "bin/tool.js", "s-other": "bin/other.mjs" } }, "sha512-yheIQXrDjpHFnPCmpw3UMtdnT49N7FqMINYsC1Tn/CAd2TOy3ifAovqygST//457xmijie1M2tqXHyrnvAwdHw=="],

    "a": ["a@1.0.0", "${urls.a}", { "dependencies": { "b": "^1.0.0" } }, "sha512-ZN8qIKY1QfDNI87yGjMJ0P+giZGVXiLIIAmYZ8rAK152GIlo+Dwq6bxxFoBOKYIZouhXnJuFIAORlsLbhuBzbQ=="],

    "b": ["b@1.0.0", "${urls.b}", {}, "sha512-adhSJ1usdqGRkLPIY2RVgacsucUkiidhiTbrqq/ibfaFRV94fo6p+dM3wTr8DyKRxMtCUKXeO70q4Dyc30dP4w=="],
  }
}
`;
}

interface Setup {
  inner: Inner;
  second: Registry;
}

// An inner workspace with the main loopback server and a second one on another
// port; `home` files go into the inner Bazel's HOME.
function setup(credential: Credential | undefined, home: Record<string, string>): Setup {
  const second = startRegistry({ archives: ARCHIVES, credential });
  const homeDir = mkdtempSync(join(process.env.TEST_TMPDIR!, "h"));
  for (const [name, text] of Object.entries(home)) writeFileSync(join(homeDir, name), text);
  const inner = new Inner("registries", { npmArchives: ARCHIVES, env: { HOME: homeDir, USERPROFILE: homeDir, NETRC: undefined } });
  cleanups.push(() => inner.close(), () => second.stop());
  return { inner, second };
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
    const { inner, second } = setup(undefined, {});
    const main = inner.registry.url;
    inner.write(".npmrc", "");
    inner.write("bun.lock", lockfile({ a: tarball(second.url, "a", "1.0.0"), s: tarball(main, "@scope/s", "1.0.0"), b: tarball(main, "b", "1.0.0") }));
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
    const { inner, second } = setup(undefined, {});
    const main = inner.registry.url;
    inner.write(".npmrc", `@scope:registry=${second.url}/\n`);
    inner.write("bun.lock", lockfile({ a: tarball(main, "a", "1.0.0"), s: "", b: tarball(main, "b", "1.0.0") }));
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
    const { inner, second } = setup(CREDENTIAL, {
      ".netrc": "machine 127.0.0.1\nlogin rules-bun-user\npassword SECRET-NETRC\n",
    });
    const main = inner.registry.url;
    inner.write(".npmrc", "");
    inner.write("bun.lock", lockfile({ a: tarball(second.url, "a", "1.0.0"), s: tarball(main, "@scope/s", "1.0.0"), b: tarball(main, "b", "1.0.0") }));
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
    const { inner, second } = setup(CREDENTIAL, { ".npmrc": "_authToken=SECRET-HOME-NPMRC\n" });
    const main = inner.registry.url;
    const host = second.url.replace(/^http:/, "");
    inner.write(".npmrc", `${host}/:_authToken=SECRET-NPMRC\n_auth=${btoa("rules-bun-user:SECRET-NPMRC")}\n`);
    inner.write("bun.lock", lockfile({ a: tarball(second.url, "a", "1.0.0"), s: tarball(main, "@scope/s", "1.0.0"), b: tarball(main, "b", "1.0.0") }));
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

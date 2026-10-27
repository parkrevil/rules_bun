// Credentials and mirrors are Bazel's downloader's (FR-009, FR-019, FR-020,
// research R3; characterization: rules_bun takes no part in these): without a
// credential the download fails naming the URL (US7-2); a credential helper
// passed with --credential_helper supplies one (US7-3); a --downloader_config
// rewrite sends the download to a mirror, whose archive is still checked
// against bun.lock (US7-5). No secret appears in a generated file or in
// `bazel mod show_repo`.

import { afterAll, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { type ArchiveSpec, type Registry, startRegistry } from "../support/npm_registry.ts";
import { rlocation } from "../support/spawn.ts";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";
import { findSecrets } from "./support/secrets.ts";

const archive = (p: string) => rlocation(`_main/bun/tests/npm/registry/archives/${p}.tgz`);
const ARCHIVES = [archive("@scope+s@1.0.0"), archive("a@1.0.0"), archive("b@1.0.0")];
const SECRET = "SECRET-HELPER";

const cleanups: (() => Promise<void> | void)[] = [];
afterAll(async () => {
  for (const cleanup of cleanups) await cleanup();
});

// The lockfile the pinned Bun 1.4.4 wrote for the workspace's package.json,
// with a's URL on `aRegistry`.
function lockfile(main: string, aRegistry: string): string {
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
    "@scope/s": ["@scope/s@1.0.0", "${main}/@scope/s/-/s-1.0.0.tgz", { "bin": { "s-tool": "bin/tool.js", "s-other": "bin/other.mjs" } }, "sha512-yheIQXrDjpHFnPCmpw3UMtdnT49N7FqMINYsC1Tn/CAd2TOy3ifAovqygST//457xmijie1M2tqXHyrnvAwdHw=="],

    "a": ["a@1.0.0", "${aRegistry}/a/-/a-1.0.0.tgz", { "dependencies": { "b": "^1.0.0" } }, "sha512-ZN8qIKY1QfDNI87yGjMJ0P+giZGVXiLIIAmYZ8rAK152GIlo+Dwq6bxxFoBOKYIZouhXnJuFIAORlsLbhuBzbQ=="],

    "b": ["b@1.0.0", "${main}/b/-/b-1.0.0.tgz", {}, "sha512-adhSJ1usdqGRkLPIY2RVgacsucUkiidhiTbrqq/ibfaFRV94fo6p+dM3wTr8DyKRxMtCUKXeO70q4Dyc30dP4w=="],
  }
}
`;
}

function registry(archives: (string | ArchiveSpec)[], bearer?: string): Registry {
  const server = startRegistry({ archives, credential: bearer ? { bearer } : undefined });
  cleanups.push(() => server.stop());
  return server;
}

function inner(origin: Registry, downloaderConfig?: (loopback: string) => string): Inner {
  const home = mkdtempSync(join(process.env.TEST_TMPDIR!, "h"));
  const session = new Inner("registries", { npmArchives: ARCHIVES, env: { HOME: home, USERPROFILE: home, NETRC: undefined }, downloaderConfig });
  cleanups.push(() => session.close());
  session.write(".npmrc", "");
  session.write("bun.lock", lockfile(session.registry.url, origin.url));
  return session;
}

const statuses = (server: Registry) => server.log.filter((e) => e.path === "/a/-/a-1.0.0.tgz").map((e) => e.status);

async function assertNoSecret(session: Inner) {
  expect(await findSecrets(session, [SECRET], ["npm", "npm__a__1.0.0"])).toEqual([]);
}

// A credential helper (Bazel's credential helper protocol: `get`, the request
// on standard input, the headers on standard output), compiled by the pinned
// Bun into a native executable under TEST_TMPDIR.
async function credentialHelper(): Promise<string> {
  const dir = mkdtempSync(join(process.env.TEST_TMPDIR!, "helper"));
  const source = join(dir, "helper.ts");
  writeFileSync(
    source,
    `await Bun.stdin.text();\nconsole.log(JSON.stringify({ headers: { Authorization: ["Bearer ${SECRET}"] } }));\n`,
  );
  const out = join(dir, process.platform === "win32" ? "helper.exe" : "helper");
  const child = Bun.spawn([process.execPath, "build", "--compile", source, "--outfile", out], { stdout: "pipe", stderr: "pipe" });
  const [stdout, stderr, exitCode] = await Promise.all([new Response(child.stdout).text(), new Response(child.stderr).text(), child.exited]);
  if (exitCode !== 0) throw new Error(`bun build --compile failed:\n${stdout}${stderr}`);
  return out;
}

test(
  "US7-2: without a credential the download fails naming the URL",
  async () => {
    const origin = registry(ARCHIVES, SECRET);
    const session = inner(origin);
    const result = await session.run(["build", "//:node_modules/a"]);
    expect(result.exitCode).not.toBe(0);
    expect(result.stderr).toContain(`Error downloading [${origin.url}/a/-/a-1.0.0.tgz]`);
    expect(result.stderr).toContain("401 Unauthorized");
    await assertNoSecret(session);
    assertOffline(session.log);
  },
  INNER_TIMEOUT,
);

test(
  "US7-3: a credential helper supplies the credential",
  async () => {
    const origin = registry(ARCHIVES, SECRET);
    const session = inner(origin);
    const helper = await credentialHelper();
    const result = await session.run(["build", "//:node_modules/a", `--credential_helper=${helper}`]);
    console.log(result.stderr.split("\n").filter((l) => /ERROR|Error/.test(l)).join("\n"));
    expect(result.exitCode, result.stderr).toBe(0);
    expect(statuses(origin)).toContain(200);
    await assertNoSecret(session);
    assertOffline(session.log);
  },
  INNER_TIMEOUT,
);

for (const altered of [false, true]) {
  test(
    `US7-5: a downloader_config rewrite sends the download to a mirror${altered ? ", whose altered archive fails integrity" : ""}`,
    async () => {
      const origin = registry([]);
      const mirror = registry(
        altered ? [{ path: archive("a@1.0.0"), serve: readFileSync(archive("b@1.0.0")) }, archive("b@1.0.0")] : ARCHIVES,
      );
      const port = (server: Registry) => server.url.split(":").pop();
      const session = inner(
        origin,
        (loopback) =>
          `rewrite ((?!127\\.0\\.0\\.1[:/]).*) ${loopback}/$1\n` +
          `rewrite 127\\.0\\.0\\.1:${port(origin)}/(.*) ${mirror.url}/$1\n`,
      );
      const result = await session.run(["build", "//:node_modules/a"]);
      console.log(result.stderr.split("\n").filter((l) => /ERROR|Error/.test(l)).join("\n"));
      expect(statuses(origin)).toEqual([]);
      expect(statuses(mirror).length).toBeGreaterThan(0);
      if (altered) {
        expect(result.exitCode).not.toBe(0);
        expect(result.stderr).toContain("Checksum");
      } else {
        expect(result.exitCode, result.stderr).toBe(0);
      }
      assertOffline(session.log);
    },
    INNER_TIMEOUT,
  );
}

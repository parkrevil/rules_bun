import { afterEach, expect, test } from "bun:test";
import { mkdtempSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { integrity, type Registry, type RegistryOptions, startRegistry } from "./npm_registry.ts";
import { packageJson, readTgz, writeTgz } from "./tar.ts";

const encoder = new TextEncoder();

function archive(dir: string, manifest: Record<string, unknown>, top = "package"): string {
  const bytes = writeTgz([
    { name: `${top}/package.json`, type: "file", data: encoder.encode(JSON.stringify(manifest)) },
    { name: `${top}/index.js`, type: "file", data: encoder.encode("module.exports = 1;\n") },
  ]);
  const path = join(dir, `${String(manifest.name).replace("/", "+")}@${manifest.version}.tgz`);
  writeFileSync(path, bytes);
  return path;
}

let registry: Registry | undefined;
afterEach(() => registry?.stop());

function start(options: RegistryOptions): Registry {
  registry = startRegistry(options);
  return registry;
}

const dir = mkdtempSync(join(process.env.TEST_TMPDIR!, "registry-"));
const a1 = archive(dir, { name: "a", version: "1.0.0" });
const a2 = archive(dir, { name: "a", version: "2.0.0", dependencies: { b: "^1.0.0" } });
const scoped = archive(dir, { name: "@scope/s", version: "1.0.0" }, "s");

test("tar entries round-trip with fixed bytes", () => {
  const entries = [
    { name: "package/package.json", type: "file" as const, data: encoder.encode("{}") },
    { name: `package/${"d/".repeat(80)}deep.js`, type: "file" as const, data: encoder.encode("x") },
  ];
  const first = writeTgz(entries);
  expect(writeTgz(entries)).toEqual(first);
  expect(readTgz(first).map((e) => e.name)).toEqual(entries.map((e) => e.name));
  expect(packageJson(first)).toEqual({});
});

test("serves a packument with every version, dist.tarball and a sha512 integrity", async () => {
  const r = start({ archives: [a1, a2] });
  const doc = await (await fetch(`${r.url}/a`)).json();
  expect(doc.name).toBe("a");
  expect(doc["dist-tags"].latest).toBe("2.0.0");
  expect(Object.keys(doc.versions)).toEqual(["1.0.0", "2.0.0"]);
  expect(doc.versions["2.0.0"].dependencies).toEqual({ b: "^1.0.0" });
  expect(doc.versions["1.0.0"].dist.tarball).toBe(`${r.url}/a/-/a-1.0.0.tgz`);
  expect(doc.versions["1.0.0"].dist.integrity).toBe(integrity(new Uint8Array(await Bun.file(a1).arrayBuffer())));
});

test("serves a scoped packument at /@scope%2fname and its tarball at /@scope/name/-/name-version.tgz", async () => {
  const r = start({ archives: [scoped] });
  const doc = await (await fetch(`${r.url}/@scope%2fs`)).json();
  expect(doc.versions["1.0.0"].dist.tarball).toBe(`${r.url}/@scope/s/-/s-1.0.0.tgz`);
  const tgz = await fetch(doc.versions["1.0.0"].dist.tarball);
  expect(new Uint8Array(await tgz.arrayBuffer())).toEqual(new Uint8Array(await Bun.file(scoped).arrayBuffer()));
});

for (const algorithm of ["sha256", "sha384", "sha512"] as const) {
  test(`writes a ${algorithm} integrity when asked`, async () => {
    const r = start({ archives: [{ path: a1, algorithm }] });
    const doc = await (await fetch(`${r.url}/a`)).json();
    expect(doc.versions["1.0.0"].dist.integrity).toStartWith(`${algorithm}-`);
  });
}

test("omits the integrity for algorithm none", async () => {
  const r = start({ archives: [{ path: a1, algorithm: "none" }] });
  const doc = await (await fetch(`${r.url}/a`)).json();
  expect(doc.versions["1.0.0"].dist.integrity).toBeUndefined();
});

test("serves replacement bytes for a tarball while keeping the packument", async () => {
  const r = start({ archives: [{ path: a1, serve: encoder.encode("altered") }] });
  expect(await (await fetch(`${r.url}/a/-/a-1.0.0.tgz`)).text()).toBe("altered");
});

test("writes dist.tarball under tarballBase and applies the packument hook", async () => {
  const r = start({
    archives: [a1],
    tarballBase: "https://registry.npmjs.org",
    packument: (name, doc) => ({ ...doc, hooked: name }),
  });
  const doc = await (await fetch(`${r.url}/a`)).json();
  expect(doc.versions["1.0.0"].dist.tarball).toBe("https://registry.npmjs.org/a/-/a-1.0.0.tgz");
  expect(doc.hooked).toBe("a");
});

test("serves static files from a path or bytes", async () => {
  const file = join(dir, "static.txt");
  writeFileSync(file, "from disk");
  const r = start({ files: { "/x/static.txt": file, "/y": encoder.encode("bytes") } });
  expect(await (await fetch(`${r.url}/x/static.txt`)).text()).toBe("from disk");
  expect(await (await fetch(`${r.url}/y`)).text()).toBe("bytes");
});

test("answers 401 without the credential and accepts Basic and Bearer", async () => {
  const r = start({ archives: [a1], credential: { basic: ["user", "secret"], bearer: "token" } });
  expect((await fetch(`${r.url}/a`)).status).toBe(401);
  const basic = `Basic ${Buffer.from("user:secret").toString("base64")}`;
  expect((await fetch(`${r.url}/a`, { headers: { authorization: basic } })).status).toBe(200);
  expect((await fetch(`${r.url}/a`, { headers: { authorization: "Bearer token" } })).status).toBe(200);
  expect((await fetch(`${r.url}/a`, { headers: { authorization: "Bearer wrong" } })).status).toBe(401);
});

test("logs every request and answers an unknown path with 404 logged as unknown", async () => {
  const r = start({ archives: [a1] });
  await fetch(`${r.url}/a`);
  expect((await fetch(`${r.url}/nothing/here`)).status).toBe(404);
  expect(r.log).toEqual([
    { method: "GET", path: "/a", status: 200, unknown: false },
    { method: "GET", path: "/nothing/here", status: 404, unknown: true },
  ]);
  expect(r.unknownPaths()).toEqual(["/nothing/here"]);
});

// Regenerates what the Bazel-in-Bazel tests serve to their inner builds
// (research G5, G10). Run by hand, with network, with the pinned Bun from the
// repository root:
//
//   $(bazel info output_base)/external/+bun+bun_linux-x64/bun bun/tests/integration/registry/update.ts
//
// It runs the pinned Bazel on the probe workspaces against the Bazel Central
// Registry, with every download rewritten to a logging proxy, once for the host
// and once per supported platform with analysis only, so the downloads of each
// platform's toolchains are seen. From what the inner builds requested it writes:
//
// - bun/tests/integration/registry/modules/: the registry files of every module
//   version the inner module graph read (MODULE.bazel, metadata.json,
//   source.json without mirror_urls, patches), and bazel_registry.json, as the
//   local registry the tests pass with --registry=file://;
// - bun/tests/integration/registry/archives.bzl: the loopback path of every
//   other download, keyed by the http_file repository that holds it;
// - the region of MODULE.bazel between the markers below: one http_file per
//   download and per Bazel binary, with the integrity the registry's
//   source.json, rules_bun's versions.bzl or the Bazel release's .sha256 file
//   gives; for a download no such file covers (a toolchain binary a module
//   fetches), the digest of the bytes the inner build accepted, which it
//   verified against the module's own integrity.

import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { integrity } from "../../support/npm_registry.ts";
import { assembleWorkspace } from "../support/inner.ts";

const BEGIN = "# BEGIN integration archives (bun/tests/integration/registry/update.ts)";
const END = "# END integration archives";
const BAZEL_VERSION = "9.2.0";
// The Bun version the nested workspaces request.
const BUN_VERSION = "1.4.4";
const BUN_PLATFORMS = ["linux-x64", "linux-aarch64", "linux-x64-musl", "linux-aarch64-musl", "darwin-x64", "darwin-aarch64", "windows-x64"];
const BAZEL_PLATFORMS = ["linux-x86_64", "linux-arm64", "darwin-x86_64", "darwin-arm64", "windows-x86_64"];
const BCR = "https://bcr.bazel.build";

// Platforms the probes analyze for: [name, os constraint, cpu constraint].
const PLATFORMS: [string, string, string][] = [
  ["linux_x64", "linux", "x86_64"],
  ["linux_aarch64", "linux", "aarch64"],
  ["macos_x64", "macos", "x86_64"],
  ["macos_aarch64", "macos", "aarch64"],
  ["windows_x64", "windows", "x86_64"],
];

// Workspaces under bun/tests/integration/workspaces/ whose builds cover every
// download an inner build makes.
const PROBES = ["toolchain"];

const root = join(import.meta.dir, "..", "..", "..", "..");
const registryDir = import.meta.dir;

interface Fetched {
  url: string;
  bytes: Uint8Array;
}

const fetched = new Map<string, Fetched>();

function startProxy() {
  return Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    idleTimeout: 0,
    async fetch(request) {
      const u = new URL(request.url);
      const url = `https:/${u.pathname}${u.search}`;
      const cached = fetched.get(url);
      if (cached) return new Response(cached.bytes);
      const response = await fetch(url);
      const bytes = new Uint8Array(await response.arrayBuffer());
      if (response.status === 200) fetched.set(url, { url, bytes });
      else console.error(`proxy: ${response.status} ${url}`);
      return new Response(bytes, { status: response.status });
    },
  });
}

async function bazelBinary(work: string): Promise<string> {
  const name = `bazel-${BAZEL_VERSION}-linux-x86_64`;
  const path = join(work, name);
  const bytes = new Uint8Array(await (await fetch(bazelUrl("linux-x86_64"))).arrayBuffer());
  writeFileSync(path, bytes, { mode: 0o755 });
  return path;
}

function bazelUrl(platform: string): string {
  const suffix = platform.startsWith("windows") ? ".exe" : "";
  return `https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-${BAZEL_VERSION}-${platform}${suffix}`;
}

async function run(bazel: string, cwd: string, outputUserRoot: string, args: string[]) {
  const child = Bun.spawn([bazel, `--output_user_root=${outputUserRoot}`, "--nosystem_rc", "--nohome_rc", ...args], {
    cwd,
    stdout: "inherit",
    stderr: "inherit",
  });
  if ((await child.exited) !== 0) throw new Error(`bazel ${args.join(" ")} failed in ${cwd}`);
}

function platformsBuild(): string {
  return PLATFORMS.map(
    ([name, os, cpu]) =>
      `platform(\n    name = "${name}",\n    constraint_values = [\n        "@platforms//os:${os}",\n        "@platforms//cpu:${cpu}",\n    ],\n)\n`,
  ).join("\n");
}

async function probe(bazel: string, workspace: string, port: number) {
  const work = mkdtempSync(join(tmpdir(), "rules-bun-probe-"));
  try {
    const ws = join(work, "ws");
    assembleWorkspace(join(registryDir, "..", "workspaces", workspace), ws, {});
    // The probe's own platforms, which need a visible @platforms.
    writeFileSync(
      join(ws, "MODULE.bazel"),
      readFileSync(join(ws, "MODULE.bazel"), "utf8") + '\nbazel_dep(name = "platforms", version = "1.1.0")\n',
    );
    mkdirSync(join(ws, "probe_platforms"));
    writeFileSync(join(ws, "probe_platforms", "BUILD.bazel"), platformsBuild());
    // A bun_binary carrying an npm package, analyzed per platform as target and
    // execution platform: its launcher and copy toolchains, the package's copy
    // toolchains and the Bun that checks a replaced archive are fetched for that
    // platform. (A test rule's implicit dependencies need a C++ toolchain for
    // the execution platform.) The package is a replaced fixture archive, so
    // nothing comes from an npm registry.
    mkdirSync(join(ws, "probe"));
    writeFileSync(join(ws, "probe", "main.ts"), "console.log(1);\n");
    const archive = readFileSync(join(root, "bun", "tests", "npm", "registry", "archives", "b@1.0.0.tgz"));
    writeFileSync(join(ws, "probe", "b.tgz"), archive);
    writeFileSync(
      join(ws, "probe", "bun.lock"),
      JSON.stringify({
        lockfileVersion: 2,
        workspaces: { "": { name: "probe", dependencies: { b: "1.0.0" } } },
        packages: { b: ["b@1.0.0", "", {}, integrity(archive, "sha512")] },
      }),
    );
    writeFileSync(join(ws, "probe", "package.json"), JSON.stringify({ name: "probe", dependencies: { b: "1.0.0" } }));
    writeFileSync(
      join(ws, "MODULE.bazel"),
      readFileSync(join(ws, "MODULE.bazel"), "utf8") +
        'npm = use_extension("@rules_bun//bun:extensions.bzl", "npm")\n' +
        'npm.translate_lock(bun_lock = "//probe:bun.lock")\n' +
        'npm.replace_package(package = "b@1.0.0", replacement = "//probe:b.tgz")\n' +
        'use_repo(npm, "npm")\n',
    );
    writeFileSync(
      join(ws, "probe", "BUILD.bazel"),
      'load("@npm//:defs.bzl", "npm_link_all_packages")\n' +
        'load("@rules_bun//bun:defs.bzl", "bun_binary")\n\n' +
        'exports_files(["b.tgz", "bun.lock"])\n\n' +
        "npm_link_all_packages()\n\n" +
        'bun_binary(\n    name = "probe",\n    entry_point = "main.ts",\n    data = ["main.ts"],\n    deps = [":node_modules/b"],\n)\n',
    );
    writeFileSync(join(work, "downloader.cfg"), `rewrite ((?!127\\.0\\.0\\.1[:/]).*) http://127.0.0.1:${port}/$1\n`);
    const common = [
      `--registry=${BCR}`,
      `--override_module=rules_bun=${root}`,
      `--repository_cache=${join(work, "cache")}`,
      `--downloader_config=${join(work, "downloader.cfg")}`,
    ];
    const our = join(work, "our");
    await run(bazel, ws, our, ["test", "//...", ...common]);
    // `bazel mod` commands evaluate every module extension of the graph, whose downloads a
    // build does not need (reproducible_test runs them).
    await run(bazel, ws, our, ["mod", "deps", "--lockfile_mode=update", ...common]);
    for (const [name] of PLATFORMS) {
      const platform = `//probe_platforms:${name}`;
      await run(bazel, ws, our, [
        "build",
        "//probe:all",
        "--nobuild",
        `--platforms=${platform}`,
        `--extra_execution_platforms=${platform}`,
        ...common,
      ]);
    }
    // Removes the output base, whose outputs are read-only, and stops the server.
    await run(bazel, ws, our, ["clean", "--expunge"]);
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

function repoName(url: string, taken: Set<string>): string {
  const parts = new URL(url).pathname.split("/").filter(Boolean);
  for (let n = 1; n <= parts.length; n++) {
    const name = `integration_${parts.slice(-n).join("_").replace(/[^A-Za-z0-9_.-]/g, "_")}`;
    if (!taken.has(name)) {
      taken.add(name);
      return name;
    }
  }
  throw new Error(`no repository name for ${url}`);
}

function sri(bytes: Uint8Array): string {
  return integrity(bytes, "sha256");
}

async function main() {
  const work = mkdtempSync(join(tmpdir(), "rules-bun-update-"));
  const proxy = startProxy();
  try {
    const bazel = await bazelBinary(work);
    for (const workspace of PROBES) await probe(bazel, workspace, proxy.port);
  } finally {
    proxy.stop(true);
    rmSync(work, { recursive: true, force: true });
  }

  // The local registry.
  const modules = join(registryDir, "modules");
  rmSync(modules, { recursive: true, force: true });
  const sourceIntegrity = new Map<string, string>();
  for (const { url, bytes } of [...fetched.values()].sort((a, b) => a.url.localeCompare(b.url))) {
    if (!url.startsWith(`${BCR}/`)) continue;
    const rel = url.slice(BCR.length + 1);
    const out = join(registryDir, rel);
    mkdirSync(dirname(out), { recursive: true });
    if (rel.endsWith("/source.json")) {
      const source = JSON.parse(new TextDecoder().decode(bytes));
      delete source.mirror_urls;
      sourceIntegrity.set(source.url, source.integrity);
      writeFileSync(out, JSON.stringify(source, null, 4) + "\n");
    } else {
      writeFileSync(out, bytes);
    }
  }

  // Integrity of the downloads a file upstream lists.
  const known = new Map(sourceIntegrity);
  const versions = readFileSync(join(root, "bun", "private", "versions.bzl"), "utf8");
  const block = versions.match(new RegExp(`"${BUN_VERSION.replaceAll(".", "\\.")}": \\{([^}]*)\\}`))?.[1];
  if (block === undefined) throw new Error(`bun/private/versions.bzl has no entry for Bun ${BUN_VERSION}`);
  const bunIntegrity = new Map([...block.matchAll(/"([a-z0-9-]+)": "(sha256-[^"]+)"/g)].map((m) => [m[1], m[2]]));
  for (const platform of BUN_PLATFORMS) {
    const value = bunIntegrity.get(platform);
    if (value === undefined) throw new Error(`bun/private/versions.bzl has no ${platform} integrity for Bun ${BUN_VERSION}`);
    known.set(`https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-${platform}.zip`, value);
  }

  const taken = new Set<string>();
  const entries: { name: string; url: string; integrity: string; executable?: boolean; file?: string }[] = [];
  const archives: [string, string][] = [];
  for (const platform of BAZEL_PLATFORMS) {
    const url = bazelUrl(platform);
    const sha = (await (await fetch(`${url}.sha256`)).text()).trim().split(/\s+/)[0];
    const name = `integration_bazel_${platform.replace("-", "_")}`;
    taken.add(name);
    // Windows starts a program only by a name with an executable extension; http_file
    // names the file "downloaded" unless told otherwise.
    const file = platform.startsWith("windows") ? "bazel.exe" : undefined;
    entries.push({ name, url, integrity: `sha256-${Buffer.from(sha, "hex").toString("base64")}`, executable: true, file });
  }
  const downloads = [...fetched.values()].filter(({ url }) => !url.startsWith(`${BCR}/`));
  for (const url of known.keys()) {
    if (url.includes("oven-sh/bun") && !fetched.has(url)) {
      const bytes = new Uint8Array(await (await fetch(url)).arrayBuffer());
      downloads.push({ url, bytes });
    }
  }
  for (const { url, bytes } of downloads.sort((a, b) => a.url.localeCompare(b.url))) {
    const actual = sri(bytes);
    const expected = known.get(url);
    if (expected !== undefined && expected.startsWith("sha256-") && expected !== actual) {
      throw new Error(`${url}: digest ${actual} differs from the published ${expected}`);
    }
    const name = repoName(url, taken);
    entries.push({ name, url, integrity: expected ?? actual });
    archives.push([name, `/${url.slice("https://".length)}`]);
  }

  // archives.bzl
  writeFileSync(
    join(registryDir, "archives.bzl"),
    [
      '"""Downloads the inner builds request, keyed by the http_file repository holding each.',
      "",
      "Written by bun/tests/integration/registry/update.ts; the value is the path the loopback",
      'server serves it at: the URL without its scheme."""',
      "",
      "ARCHIVES = {",
      ...archives.map(([name, path]) => `    "${name}": "${path}",`),
      "}",
      "",
    ].join("\n"),
  );

  // MODULE.bazel region
  const modulePath = join(root, "MODULE.bazel");
  const text = readFileSync(modulePath, "utf8");
  const begin = text.indexOf(BEGIN);
  const end = text.indexOf(END);
  if (begin === -1 || end === -1 || end < begin) {
    throw new Error(`MODULE.bazel must hold the lines "${BEGIN}" and "${END}"`);
  }
  const region = [
    BEGIN,
    'http_file = use_repo_rule("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")',
    "",
    ...entries.map((e) =>
      [
        "http_file(",
        `    name = "${e.name}",`,
        "    dev_dependency = True,",
        ...(e.file ? [`    downloaded_file_path = "${e.file}",`] : []),
        ...(e.executable ? ["    executable = True,"] : []),
        `    integrity = "${e.integrity}",`,
        `    urls = ["${e.url}"],`,
        ")",
        "",
      ].join("\n"),
    ),
    END,
  ].join("\n");
  writeFileSync(modulePath, text.slice(0, begin) + region + text.slice(end + END.length));
  rmSync(work, { recursive: true, force: true });
  console.log(`${entries.length} http_file repositories; ${archives.length} served downloads`);
}

await main();

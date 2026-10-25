// A loopback npm registry for the npm tests (research R15): packuments and
// tarballs built from package archives, arbitrary static files, an optional
// credential, and a log of every request it answered.

import { readFileSync } from "node:fs";
import { packageJson } from "./tar.ts";

export type IntegrityAlgorithm = "sha256" | "sha384" | "sha512" | "none";

export interface ArchiveSpec {
  /** Path of the `.tgz` file the packument is built from. */
  path: string;
  /** Algorithm of `dist.integrity`; "none" omits it. Default "sha512". */
  algorithm?: IntegrityAlgorithm;
  /** Bytes to serve instead of the file's, keeping the packument of the file. */
  serve?: Uint8Array;
}

export interface Credential {
  /** Accepted `Authorization: Basic` user and password. */
  basic?: [string, string];
  /** Accepted `Authorization: Bearer` token. */
  bearer?: string;
}

export interface RegistryOptions {
  archives?: (string | ArchiveSpec)[];
  /** URL path (starting with "/") to a file path or to bytes. */
  files?: Record<string, string | Uint8Array>;
  /** When set, every request without it is answered with 401. */
  credential?: Credential;
  /** Base URL written into `dist.tarball`; default the registry's own URL. */
  tarballBase?: string;
  /** Changes a packument before it is served. */
  packument?: (name: string, packument: Record<string, any>) => Record<string, any>;
}

export interface LogEntry {
  method: string;
  path: string;
  status: number;
  unknown: boolean;
}

export interface Registry {
  /** `http://127.0.0.1:<port>`, without a trailing slash. */
  url: string;
  port: number;
  log: LogEntry[];
  /** Paths of the requests answered as unknown (404). */
  unknownPaths(): string[];
  stop(): void;
}

/** Returns the SRI string of `bytes` for `algorithm`. */
export function integrity(bytes: Uint8Array, algorithm: Exclude<IntegrityAlgorithm, "none"> = "sha512"): string {
  return `${algorithm}-${new Bun.CryptoHasher(algorithm).update(bytes).digest("base64")}`;
}

/** The path of a package's tarball: `/{name}/-/{basename}-{version}.tgz`. */
export function tarballPath(name: string, version: string): string {
  const basename = name.includes("/") ? name.slice(name.indexOf("/") + 1) : name;
  return `/${name}/-/${basename}-${version}.tgz`;
}

interface Version {
  manifest: Record<string, any>;
  bytes: Uint8Array;
  served: Uint8Array;
  algorithm: IntegrityAlgorithm;
}

function authorized(request: Request, credential: Credential): boolean {
  const header = request.headers.get("authorization") ?? "";
  if (credential.bearer !== undefined && header === `Bearer ${credential.bearer}`) return true;
  if (credential.basic !== undefined) {
    const [user, password] = credential.basic;
    if (header === `Basic ${Buffer.from(`${user}:${password}`).toString("base64")}`) return true;
  }
  return false;
}

/** Starts the registry on 127.0.0.1 with a free port. */
export function startRegistry(options: RegistryOptions = {}): Registry {
  const packages = new Map<string, Map<string, Version>>();
  for (const spec of options.archives ?? []) {
    const { path, algorithm = "sha512", serve } = typeof spec === "string" ? { path: spec } : spec;
    const bytes = new Uint8Array(readFileSync(path));
    const manifest = packageJson(bytes);
    if (!packages.has(manifest.name)) packages.set(manifest.name, new Map());
    packages.get(manifest.name)!.set(manifest.version, { manifest, bytes, served: serve ?? bytes, algorithm });
  }
  const tarballs = new Map<string, Version>();
  for (const [name, versions] of packages) {
    for (const [version, v] of versions) tarballs.set(tarballPath(name, version), v);
  }

  const log: LogEntry[] = [];
  let base = "";

  function packument(name: string, versions: Map<string, Version>): Record<string, any> {
    const sorted = [...versions.keys()].sort(Bun.semver.order);
    const tarballBase = options.tarballBase ?? base;
    const doc: Record<string, any> = {
      name,
      "dist-tags": { latest: sorted[sorted.length - 1] },
      versions: Object.fromEntries(
        sorted.map((version) => {
          const v = versions.get(version)!;
          const dist: Record<string, string> = { tarball: `${tarballBase}${tarballPath(name, version)}` };
          if (v.algorithm !== "none") dist.integrity = integrity(v.bytes, v.algorithm);
          return [version, { ...v.manifest, dist }];
        }),
      ),
    };
    return options.packument ? options.packument(name, doc) : doc;
  }

  function answer(request: Request, path: string): { response: Response; unknown: boolean } {
    if (options.credential !== undefined && !authorized(request, options.credential)) {
      return { response: new Response("unauthorized", { status: 401 }), unknown: false };
    }
    const file = options.files?.[path];
    if (file !== undefined) {
      return { response: new Response(typeof file === "string" ? Bun.file(file) : file), unknown: false };
    }
    const tarball = tarballs.get(path);
    if (tarball !== undefined) return { response: new Response(tarball.served), unknown: false };
    const versions = packages.get(path.slice(1));
    if (versions !== undefined) return { response: Response.json(packument(path.slice(1), versions)), unknown: false };
    return { response: new Response("not found", { status: 404 }), unknown: true };
  }

  const server = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch(request) {
      const raw = new URL(request.url).pathname;
      let path = raw;
      try {
        path = decodeURIComponent(raw);
      } catch {}
      const { response, unknown } = answer(request, path);
      log.push({ method: request.method, path: raw, status: response.status, unknown });
      return response;
    },
  });
  base = `http://127.0.0.1:${server.port}`;

  return {
    url: base,
    port: server.port,
    log,
    unknownPaths: () => log.filter((e) => e.unknown).map((e) => e.path),
    stop: () => server.stop(true),
  };
}

// The linked dependency graph of FR-008 (contracts/conformance-graph.md): reading Bun's from the
// node_modules its isolated install wrote (research R7), and comparing two graphs by partition
// refinement (research R8).

import { existsSync, lstatSync, readdirSync, readFileSync, realpathSync } from "node:fs";
import { join } from "node:path";

/** A target: `e:<index>` (an entry) or `w:<path>` (a workspace). */
export type Target = string;

export interface Entry {
  name: string;
  version: string;
  links: Record<string, Target>;
  /** Ruleset side only: why the hub fails analysis of this instance (`status` other than `ok`). */
  status?: string;
  /** Ruleset side only: `status` is because rules_bun does not fetch the entry (ID-4). */
  unfetched?: boolean;
  /** Bun side only: for an entry Bun installed from another resolution than a registry version (its
   * store directory is not DOC-ISO's `<package>@<version>` form of its name and version, T127), the
   * resolution of the `bun.lock` row whose store key names that directory, as slot 0 writes it after
   * `<name>@` (`file:a`, a tarball URL, a local tarball), which identifies it (T172, T175); absent for a registry package. */
  resolution?: string;
}

export interface Graph {
  /** Workspace path (`""` for the root) → dependency name → target. */
  holders: Record<string, Record<string, Target>>;
  entries: Entry[];
  /** Ruleset side only: workspace path → store directory (`name@version[+<peer hash>]`) its links
   * reach as several entries, which one target cannot hold (run.bzl `_check_unique`) → each of
   * those entries → the holder's links (dependency names) whose closure carries it. */
  conflicts?: Record<string, Record<string, Record<Target, string[]>>>;
}

export type Tuple = [string | null, string | null, string | null];

export interface PlatformClass {
  platforms: Tuple[];
  graph: Graph;
}

/** The symlinks (junctions on Windows) of a `node_modules`: name → real path. Scoped names are one
 * level down; `.bin` and other dot entries are skipped. */
function symlinks(nodeModules: string): Map<string, string> {
  const found = new Map<string, string>();
  if (!existsSync(nodeModules)) return found;
  for (const name of readdirSync(nodeModules).sort()) {
    if (name.startsWith(".")) continue;
    const names = name.startsWith("@") ? readdirSync(join(nodeModules, name)).sort().map((inner) => `${name}/${inner}`) : [name];
    for (const n of names) {
      const path = join(nodeModules, n);
      if (lstatSync(path).isSymbolicLink()) found.set(n, realpathSync(path));
    }
  }
  return found;
}

/** The package folders a store directory holds (not symlinks): name → real path. */
function ownFolders(nodeModules: string): Map<string, string> {
  const found = new Map<string, string>();
  for (const name of readdirSync(nodeModules).sort()) {
    if (name.startsWith(".")) continue;
    const names = name.startsWith("@") ? readdirSync(join(nodeModules, name)).sort().map((inner) => `${name}/${inner}`) : [name];
    for (const n of names) {
      const path = join(nodeModules, n);
      if (!lstatSync(path).isSymbolicLink() && lstatSync(path).isDirectory()) found.set(n, realpathSync(path));
    }
  }
  return found;
}

/** `String::fmt_store_path`: `bytes` as one path component of the isolated store.
 *
 * Bun: src/semver/lib.rs L657–L686 @ bun-v1.4.4 */
function storePath(text: string): string {
  return text.replace(/[/\\:#?]/g, "+");
}

/** `write_resolution`: a resolution of at most 80 bytes as written, a longer one as its first 63
 * bytes (back to a character boundary) and `+<16 hex digits of its wyhash>`.
 *
 * Bun: src/install/isolated_install/Store.rs L341–L344, L366–L384 @ bun-v1.4.4 */
function boundedResolution(text: string): string {
  const bytes = new TextEncoder().encode(text);
  if (bytes.length <= 80) return text;
  let cut = 80 - 1 - 16;
  while (cut > 0 && (bytes[cut] & 0xc0) === 0x80) cut--;
  return `${new TextDecoder().decode(bytes.subarray(0, cut))}+${Bun.hash.wyhash(text).toString(16).padStart(16, "0")}`;
}

/** `fmt_store_url`: a tarball URL without its userinfo and query string, with the wyhash of the
 * whole URL in their place when it has either.
 *
 * Bun: src/install/resolution.rs L587–L619, L640–L656 @ bun-v1.4.4 */
function storeURL(url: string): string {
  const colon = url.indexOf(":");
  const authorityStart = colon >= 0 && url.startsWith("//", colon + 1) ? colon + "://".length : 0;
  const authorityEnd = url.slice(authorityStart).search(/[/?#]/);
  const authority = url.slice(authorityStart, authorityEnd < 0 ? url.length : authorityStart + authorityEnd);
  const at = authority.lastIndexOf("@");
  const hostStart = at < 0 ? authorityStart : authorityStart + at + 1;
  const query = url.indexOf("?", hostStart);
  const queryStart = query < 0 ? url.length : query;
  const hash = hostStart !== authorityStart || queryStart !== url.length ? `+${Bun.hash.wyhash(url).toString(16).padStart(16, "0")}` : "";
  return `${storePath(url.slice(0, authorityStart))}${storePath(url.slice(hostStart, queryStart))}${hash}`;
}

/** The store key Bun gives a package of `name` at a `bun.lock` resolution (slot 0 after `<name>@`)
 * that is a folder (`file:`), a tarball URL or a local tarball, without the `+<peer hash>`;
 * `undefined` for any other resolution, whose key this test does not carry over (T172).
 * `Resolution::from_text_lockfile` reads `file:` as a folder, and a resolution `Tag::infer` reads
 * as a tarball that is no URL as a local tarball, whose store path is its path (T175): here a
 * resolution without a protocol ending in `.tgz`, `.tar.gz` or `.tar` (`is_tarball`), such as
 * `loc-1.0.0.tgz` for a `file:loc-1.0.0.tgz` dependency (bun_install_types.bzl
 * `resolution_from_text_lockfile`, `is_tarball`).
 *
 * Bun: src/install/isolated_install/Store.rs L386–L428 @ bun-v1.4.4
 * Bun: src/install/resolution.rs L192–L201, L541–L585 @ bun-v1.4.4 */
function storeKey(name: string, resolution: string): string | undefined {
  if (resolution.startsWith("file:")) return `${storePath(name)}@${boundedResolution(`file+${storePath(resolution.slice("file:".length))}`)}`;
  if (/^https?:\/\//.test(resolution)) return `${storePath(name)}@${boundedResolution(storeURL(resolution))}`;
  if (!resolution.includes(":") && /\.(tgz|tar\.gz|tar)$/i.test(resolution)) return `${storePath(name)}@${boundedResolution(storePath(resolution))}`;
  return undefined;
}

/** The resolution of the `bun.lock` row of `name` whose store key names `storeDir`, alone or with
 * Bun's `+<peer hash>` (16 hexadecimal digits); an exact key wins over one with a peer hash. */
function resolutionOf(lock: Record<string, any>, name: string, storeDir: string): string | undefined {
  const exact: string[] = [];
  const peered: string[] = [];
  for (const row of Object.values((lock.packages ?? {}) as Record<string, unknown[]>)) {
    const spec = typeof row[0] === "string" ? row[0] : "";
    if (!spec.startsWith(`${name}@`)) continue;
    const resolution = spec.slice(name.length + 1);
    const key = storeKey(name, resolution);
    if (key === undefined) continue;
    if (storeDir === key) exact.push(resolution);
    else if (storeDir.startsWith(`${key}+`) && /^[0-9a-f]{16}$/.test(storeDir.slice(key.length + 1))) peered.push(resolution);
  }
  const found = [...new Set(exact.length > 0 ? exact : peered)];
  if (found.length > 1) throw new Error(`Bun's store directory ${storeDir} is the store key of several bun.lock resolutions of ${name}: ${found.join(", ")}`);
  return found[0];
}

/**
 * Reads the graph Bun's isolated install linked in `dir` (research R7): holders are the root and
 * each workspace path; entries are the store directories `node_modules/.bun/<dir>` except
 * `node_modules/.bun/node_modules` (ID-3); an entry's identity is the `name` and `version` of its
 * package's `package.json`, never its directory name. The directory tells whether the entry is
 * a registry package: DOC-ISO names its store directory `<package>@<version>` (a scope's `/` written
 * `+`), to which Bun appends `+<peer hash>` for a package with peers; any other name is of a package
 * installed from another resolution (T127), identified by the `bun.lock` resolution whose store key
 * names the directory (`file:` folders, tarball URLs and local tarballs; any other fails the read, T172, T175).
 */
export function readBunGraph(dir: string, workspaces: string[]): Graph {
  const entries: Entry[] = [];
  let lock: Record<string, any> | undefined;
  const index = new Map<string, number>();
  const ownLinks: { entry: number; nodeModules: string; own: string }[] = [];
  const store = join(dir, "node_modules", ".bun");
  if (existsSync(store)) {
    for (const storeDir of readdirSync(store).sort()) {
      if (storeDir === "node_modules" || storeDir.startsWith(".")) continue;
      const nodeModules = join(store, storeDir, "node_modules");
      if (!existsSync(nodeModules)) continue;
      for (const [own, real] of ownFolders(nodeModules)) {
        const manifest = JSON.parse(readFileSync(join(real, "package.json"), "utf8"));
        index.set(real, entries.length);
        ownLinks.push({ entry: entries.length, nodeModules, own });
        const registryDir = `${String(manifest.name).replace("/", "+")}@${manifest.version}`;
        if (storeDir === registryDir || storeDir.startsWith(`${registryDir}+`)) {
          entries.push({ name: manifest.name, version: manifest.version, links: {} });
          continue;
        }
        lock ??= Bun.JSONC.parse(readFileSync(join(dir, "bun.lock"), "utf8")) as Record<string, any>;
        const resolution = resolutionOf(lock, manifest.name, storeDir);
        if (resolution === undefined) {
          throw new Error(
            `Bun's store directory ${storeDir} in ${dir} is neither ${registryDir} nor the store key of a file:, tarball URL or local tarball resolution of ${manifest.name} in bun.lock, the forms graph.ts carries Bun's store key over for`,
          );
        }
        entries.push({ name: manifest.name, version: manifest.version, links: {}, resolution });
      }
    }
  }
  const workspaceOf = new Map<string, string>();
  for (const path of workspaces) workspaceOf.set(realpathSync(join(dir, path)), path);
  const target = (real: string): Target => {
    const entry = index.get(real);
    if (entry !== undefined) return `e:${entry}`;
    const workspace = workspaceOf.get(real);
    if (workspace !== undefined) return `w:${workspace}`;
    throw new Error(`a link of Bun's install in ${dir} resolves to ${real}, which is neither a store entry nor a workspace`);
  };
  for (const { entry, nodeModules, own } of ownLinks) {
    for (const [name, real] of symlinks(nodeModules)) if (name !== own) entries[entry].links[name] = target(real);
  }
  const holders: Graph["holders"] = {};
  for (const path of workspaces) {
    holders[path] = {};
    for (const [name, real] of symlinks(join(dir, path, "node_modules"))) holders[path][name] = target(real);
  }
  return { holders, entries };
}

interface Node {
  side: "ruleset" | "bun";
  label: string;
  /** `""` for the root, a workspace path, or `undefined` for an entry. */
  holder?: string;
  entry?: Entry;
  links: Record<string, string>;
}

/** What identifies an entry beside its name (T127, T172): a registry package's version, or the
 * resolution of a package installed from another, which bun.lock records instead of a version: in
 * the ruleset its version, in Bun the resolution `readBunGraph` found for its store directory (the
 * version its package.json holds is not compared, as the ruleset does not know it). */
function identity(entry: Entry): string {
  return entry.resolution ?? entry.version;
}

function nodes(side: Node["side"], graph: Graph): Map<string, Node> {
  const result = new Map<string, Node>();
  const id = (target: Target) => `${side}:${target.startsWith("w:") ? `h:${target.slice(2)}` : target}`;
  const ids = (links: Record<string, Target>) => Object.fromEntries(Object.entries(links).map(([name, t]) => [name, id(t)]));
  for (const [path, links] of Object.entries(graph.holders)) result.set(`${side}:h:${path}`, { side, label: `h:${path}`, holder: path, links: ids(links) });
  graph.entries.forEach((entry, i) => {
    // Each entry is labelled by its own resolution (T127, T172): a registry package by its name and
    // version, any other by its name and the resolution bun.lock records for it, on both sides, so
    // a registry entry and a non-registry entry of one name never compare equal, nor two
    // non-registry entries of one name from different resolutions.
    const label = `e:${entry.name}@${identity(entry)}`;
    result.set(`${side}:e:${i}`, { side, label, entry, links: ids(entry.links) });
  });
  return result;
}

/** Partition refinement of the disjoint union of both graphs (research R8): node → class. */
function refine(all: Map<string, Node>): Map<string, number> {
  let classes = new Map<string, number>();
  const labels = new Map<string, number>();
  for (const [id, node] of all) {
    if (!labels.has(node.label)) labels.set(node.label, labels.size);
    classes.set(id, labels.get(node.label)!);
  }
  let count = labels.size;
  for (;;) {
    const signatures = new Map<string, number>();
    const next = new Map<string, number>();
    for (const [id, node] of all) {
      const links = Object.entries(node.links)
        .map(([name, target]) => [name, all.has(target) ? classes.get(target)! : -1] as const)
        .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
      const signature = JSON.stringify([classes.get(id), links]);
      if (!signatures.has(signature)) signatures.set(signature, signatures.size);
      next.set(id, signatures.get(signature)!);
    }
    classes = next;
    if (signatures.size === count) return classes;
    count = signatures.size;
  }
}

function nameVersion(node: Node | undefined): string {
  if (node === undefined) return "no link";
  if (node.holder !== undefined) return node.holder === "" ? "the root" : `workspace "${node.holder}"`;
  return `${node.entry!.name}@${identity(node.entry!)}`;
}

/** An entry with its bindings, one level deep: `p@1.0.0 (q → q@1.0.0)`. */
function describe(all: Map<string, Node>, node: Node | undefined, except?: string): string {
  if (node === undefined || node.holder !== undefined) return nameVersion(node);
  const bindings = Object.keys(node.links)
    .filter((name) => name !== except)
    .sort()
    .map((name) => `${name} → ${nameVersion(all.get(node.links[name]))}`);
  return bindings.length === 0 ? nameVersion(node) : `${nameVersion(node)} (${bindings.join(", ")})`;
}

/**
 * Compares the ruleset's graph of `project` with Bun's (FR-008). Returns `undefined` when they are
 * equal, otherwise the first difference in the contract's failure text (FR-012).
 */
export function compare(project: string, ruleset: Graph, bun: Graph): string | undefined {
  const all = new Map([...nodes("ruleset", ruleset), ...nodes("bun", bun)]);
  const classes = refine(all);
  const paths = [...new Set([...Object.keys(ruleset.holders), ...Object.keys(bun.holders)])].sort();
  for (const path of paths) {
    if (!(path in bun.holders)) return holderOnly(project, all, `ruleset:h:${path}`, ["the ruleset", "Bun"]);
    if (!(path in ruleset.holders)) return holderOnly(project, all, `bun:h:${path}`, ["Bun", "the ruleset"]);
  }
  // Walk the pairs of corresponding nodes from the holders down to the first link that differs.
  const queue: [string, string][] = paths.map((path) => [`ruleset:h:${path}`, `bun:h:${path}`]);
  const seen = new Set<string>();
  for (let i = 0; i < queue.length; i++) {
    const [r, b] = queue[i];
    if (classes.get(r) === classes.get(b) || seen.has(`${r} ${b}`)) continue;
    seen.add(`${r} ${b}`);
    const rNode = all.get(r)!;
    const bNode = all.get(b)!;
    const names = [...new Set([...Object.keys(rNode.links), ...Object.keys(bNode.links)])].sort();
    const deeper: [string, string][] = [];
    for (const name of names) {
      const rTarget = all.get(rNode.links[name]);
      const bTarget = all.get(bNode.links[name]);
      if (rTarget !== undefined && bTarget !== undefined && classes.get(rNode.links[name]) === classes.get(bNode.links[name])) continue;
      if (rTarget === undefined || bTarget === undefined || rTarget.label !== bTarget.label) {
        const where = describe(all, rNode, name);
        return `${project}: ${where} links "${name}" to ${describe(all, rTarget)}, Bun links it to ${describe(all, bTarget)}`;
      }
      deeper.push([rNode.links[name], bNode.links[name]]);
    }
    queue.push(...deeper);
  }
  // Holders agree all the way down: entry counts (research R8).
  const counts = new Map<number, { ruleset: number; bun: number; node: Node }>();
  for (const [id, node] of all) {
    const c = classes.get(id)!;
    if (!counts.has(c)) counts.set(c, { ruleset: 0, bun: 0, node });
    counts.get(c)![node.side]++;
  }
  const unequal = [...counts.values()].find(({ ruleset: r, bun: b }) => r !== b);
  if (unequal !== undefined) return countDifference(project, all, classes, counts, paths) ?? unreached(project, all, unequal);
  // Linked alike, but one target cannot hold the entries a holder's links reach, while Bun links each.
  for (const [path, found] of Object.entries(ruleset.conflicts ?? {}).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))) {
    const where = path === "" ? "the root's" : `workspace "${path}"'s`;
    for (const [directory, reaching] of Object.entries(found).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))) {
      const each = Object.entries(reaching)
        .map(([target, names]) => `${describe(all, all.get(`ruleset:${target}`))} through ${names.map((name) => `"${name}"`).join(", ")}`)
        .sort();
      return `${project}: ${where} links reach ${each.length} entries of ${directory}, which run.bzl fails analysis of in one target, while Bun links each: ${each.join("; ")}`;
    }
  }
  // Linked alike, but an entry the hub fails analysis of cannot be used, while Bun installs it;
  // except an entry rules_bun does not fetch, which ID-4 lets fail analysis (its links are compared
  // above like any other's).
  return failedAnalysis(project, all, paths);
}

/** Whether the hub fails analysis of a node's entry for a reason other than ID-4's. */
function failsAnalysis(node: Node | undefined): boolean {
  return node?.entry?.status !== undefined && !node.entry.unfetched;
}

/**
 * The failure of an entry the hub fails analysis of (FR-012): walking the corresponding nodes from
 * the holders down (each pair is of one class, as every link agrees), the first link whose ruleset
 * target fails analysis, with its dependent and both sides' targets. `undefined` when no entry
 * fails analysis.
 */
function failedAnalysis(project: string, all: Map<string, Node>, paths: string[]): string | undefined {
  const queue: [string, string][] = paths.map((path) => [`ruleset:h:${path}`, `bun:h:${path}`]);
  const seen = new Set(queue.map(([r, b]) => `${r} ${b}`));
  for (let i = 0; i < queue.length; i++) {
    const [r, b] = queue[i];
    const rNode = all.get(r)!;
    const bNode = all.get(b)!;
    for (const name of Object.keys(rNode.links).sort()) {
      const rTarget = all.get(rNode.links[name]);
      const bTarget = all.get(bNode.links[name]);
      if (failsAnalysis(rTarget)) {
        const where = describe(all, rNode, name);
        return `${project}: ${where} links "${name}" to ${describe(all, rTarget)}, which fails analysis in the ruleset (${rTarget!.entry!.status}), Bun links it to ${describe(all, bTarget)} and installs it`;
      }
      if (rTarget === undefined || bTarget === undefined || seen.has(`${rNode.links[name]} ${bNode.links[name]}`)) continue;
      seen.add(`${rNode.links[name]} ${bNode.links[name]}`);
      queue.push([rNode.links[name], bNode.links[name]]);
    }
  }
  const node = [...all.values()].find(failsAnalysis);
  return node === undefined ? undefined : `${project}: ${describe(all, node)} fails analysis in the ruleset (${node.entry!.status}), Bun installs it: no holder reaches it`;
}

/** The failure of a holder on one side only (FR-012): each of its links with its target, which the
 * other side, lacking the holder, links to nothing. */
function holderOnly(project: string, all: Map<string, Node>, id: string, [side, other]: [string, string]): string {
  const node = all.get(id)!;
  const prefix = `${project}: ${nameVersion(node)} is a holder in ${side} only`;
  const names = Object.keys(node.links).sort();
  if (names.length === 0) return `${prefix} and links nothing`;
  const links = names.map((name) => `"${name}" to ${describe(all, all.get(node.links[name]))}`);
  const listed = links.length === 1 ? links[0] : `${links.slice(0, -1).join(", ")} and ${links[links.length - 1]}`;
  return `${prefix}: ${side} links ${listed}, ${other} links ${names.length === 1 ? "it" : "them"} to no link`;
}

/** A link that `countDifference` names: `name` of `dependent`, which the walk reached from `holder`. */
interface Via {
  dependent: string;
  name: string;
  holder: string;
}

/** A dependent with its other bindings and the holder that reaches it: `b@1.0.0 (y → y@1.0.0,
 * reached from the root)`, or the holder itself. */
function dependent(all: Map<string, Node>, via: Via): string {
  const node = all.get(via.dependent)!;
  if (node.holder !== undefined) return nameVersion(node);
  const bindings = Object.keys(node.links)
    .filter((name) => name !== via.name)
    .sort()
    .map((name) => `${name} → ${nameVersion(all.get(node.links[name]))}`);
  const holder = via.holder === "" ? "the root" : `workspace "${via.holder}"`;
  return `${nameVersion(node)} (${[...bindings, `reached from ${holder}`].join(", ")})`;
}

/**
 * The entry-count failure with the two links that show it (FR-012): walking the corresponding
 * nodes from the holders down (each pair is of one class, so their links have the same names and
 * target classes), the first link that binds to an entry of a class with more entries on one side
 * whose counterpart another link already reached with a different entry of that side, where the
 * other side binds both to one entry. `undefined` when no such pair of links is reached.
 */
function countDifference(
  project: string,
  all: Map<string, Node>,
  classes: Map<string, number>,
  counts: Map<number, { ruleset: number; bun: number }>,
  paths: string[],
): string | undefined {
  // Each node of one side → the first node of the other side it was paired with, and by which link.
  const pairedR = new Map<string, { other: string; via: Via }>();
  const pairedB = new Map<string, { other: string; via: Via }>();
  const queue: [string, string, string][] = paths.map((path) => [`ruleset:h:${path}`, `bun:h:${path}`, path]);
  const seen = new Set<string>();
  for (let i = 0; i < queue.length; i++) {
    const [r, b, holder] = queue[i];
    const rNode = all.get(r)!;
    const bNode = all.get(b)!;
    for (const name of Object.keys(rNode.links).sort()) {
      const rTarget = rNode.links[name];
      const bTarget = bNode.links[name];
      if (!all.has(rTarget) || !all.has(bTarget)) continue;
      const via = { dependent: r, name, holder };
      const { ruleset: rCount, bun: bCount } = counts.get(classes.get(rTarget)!)!;
      const entry = describe(all, all.get(rTarget));
      const prefix = `${project}: ${entry} is ${rCount} entries in the ruleset, Bun installs it as ${bCount}`;
      const priorB = pairedB.get(bTarget);
      if (rCount > bCount && priorB !== undefined && priorB.other !== rTarget) {
        return `${prefix}: ${dependent(all, via)} links "${name}" to another entry of it than ${dependent(all, priorB.via)} links "${priorB.via.name}" to, Bun links both to one`;
      }
      const priorR = pairedR.get(rTarget);
      if (rCount < bCount && priorR !== undefined && priorR.other !== bTarget) {
        return `${prefix}: ${dependent(all, via)} links "${name}" to the entry of it ${dependent(all, priorR.via)} links "${priorR.via.name}" to, Bun links them to two`;
      }
      if (!pairedB.has(bTarget)) pairedB.set(bTarget, { other: rTarget, via });
      if (!pairedR.has(rTarget)) pairedR.set(rTarget, { other: bTarget, via });
      if (!seen.has(`${rTarget} ${bTarget}`)) {
        seen.add(`${rTarget} ${bTarget}`);
        queue.push([rTarget, bTarget, holder]);
      }
    }
  }
  return undefined;
}

/** The entry-count failure when every link that reaches the class pairs one entry with one: the
 * side with more holds an entry no holder reaches. */
function unreached(project: string, all: Map<string, Node>, { ruleset: r, bun: b, node }: { ruleset: number; bun: number; node: Node }): string {
  return `${project}: ${describe(all, node)} is ${r} entries in the ruleset, Bun installs it as ${b}: no holder reaches ${r > b ? "the ruleset's" : "Bun's"} extra entry`;
}

/** A project's failure (contract "Failure text"): the ruleset's evaluation error, or `compare`'s
 * first difference. With Bun 1.4.2 as the oracle (US5), a difference of a graph the ruleset linked
 * is a disagreement of Bun 1.4.2 with Bun 1.4.4, which the ruleset follows (FR-013); a ruleset
 * failure follows neither, so it stays the ruleset's (T167). */
export function projectDifference(project: string, ruleset: Graph | { error: string }, bun: Graph, oracle: "1.4.4" | "1.4.2"): string | undefined {
  if ("error" in ruleset) return `${project}: the ruleset fails (${ruleset.error}), Bun installs the lockfile`;
  const difference = compare(project, ruleset, bun);
  if (oracle === "1.4.4" || difference === undefined) return difference;
  return `${project}: Bun 1.4.2 links this lockfile differently from Bun 1.4.4, which the ruleset follows (${difference.slice(project.length + 2)}); the ruleset cannot follow both (constitution V)`;
}

/** The host's platform tuple in npm values (research R8); the C library on Linux as Node reports it. */
export function hostTuple(): Tuple {
  if (process.platform !== "linux") return [process.platform, process.arch, null];
  const header = (process as any).report?.getReport?.().header ?? {};
  return ["linux", process.arch, header.glibcVersionRuntime ? "glibc" : "musl"];
}

/** The ruleset's class holding `tuple`. */
export function classFor(tuple: Tuple, classes: PlatformClass[]): PlatformClass {
  const found = classes.find((c) => c.platforms.some((p) => p[0] === tuple[0] && p[1] === tuple[1] && p[2] === tuple[2]));
  if (found === undefined) throw new Error(`no platform class of the ruleset holds ${JSON.stringify(tuple)}`);
  return found;
}

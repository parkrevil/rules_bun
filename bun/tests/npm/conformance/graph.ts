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
}

export interface Graph {
  /** Workspace path (`""` for the root) → dependency name → target. */
  holders: Record<string, Record<string, Target>>;
  entries: Entry[];
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

/**
 * Reads the graph Bun's isolated install linked in `dir` (research R7): holders are the root and
 * each workspace path; entries are the store directories `node_modules/.bun/<dir>` except
 * `node_modules/.bun/node_modules` (ID-3); an entry's identity is the `name` and `version` of its
 * package's `package.json`, never its directory name.
 */
export function readBunGraph(dir: string, workspaces: string[]): Graph {
  const entries: Entry[] = [];
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
        entries.push({ name: manifest.name, version: manifest.version, links: {} });
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

// An exact npm version (semver.org 2.0.0 grammar, loosely): what bun.lock records for a registry
// package. Any other version is a resolution (file:, a URL, ...), for which bun.lock records no
// version, so the ruleset cannot know the one the package.json Bun installed holds.
const EXACT_VERSION = /^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$/;

function nodes(side: Node["side"], graph: Graph, byName: Set<string>): Map<string, Node> {
  const result = new Map<string, Node>();
  const id = (target: Target) => `${side}:${target.startsWith("w:") ? `h:${target.slice(2)}` : target}`;
  const ids = (links: Record<string, Target>) => Object.fromEntries(Object.entries(links).map(([name, t]) => [name, id(t)]));
  for (const [path, links] of Object.entries(graph.holders)) result.set(`${side}:h:${path}`, { side, label: `h:${path}`, holder: path, links: ids(links) });
  graph.entries.forEach((entry, i) => {
    // A package the ruleset holds at no registry version is identified by its name on both sides.
    const label = byName.has(entry.name) ? `e:${entry.name}@(not a registry version)` : `e:${entry.name}@${entry.version}`;
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
  return `${node.entry!.name}@${node.entry!.version}`;
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
  const byName = new Set(ruleset.entries.filter((e) => !EXACT_VERSION.test(e.version)).map((e) => e.name));
  const all = new Map([...nodes("ruleset", ruleset, byName), ...nodes("bun", bun, byName)]);
  const classes = refine(all);
  const paths = [...new Set([...Object.keys(ruleset.holders), ...Object.keys(bun.holders)])].sort();
  for (const path of paths) {
    const where = path === "" ? "the root" : `workspace "${path}"`;
    if (!(path in bun.holders)) return `${project}: ${where} is a holder in the ruleset only`;
    if (!(path in ruleset.holders)) return `${project}: ${where} is a holder in Bun only`;
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
  for (const { ruleset: r, bun: b, node } of counts.values()) {
    if (r !== b) return `${project}: ${describe(all, node)} is ${r} entries in the ruleset, Bun installs it as ${b}`;
  }
  // Linked alike, but an entry the hub fails analysis of cannot be used, while Bun installs it.
  for (const node of all.values()) {
    if (node.entry?.status !== undefined) return `${project}: ${describe(all, node)} fails analysis in the ruleset (${node.entry.status}), Bun installs it`;
  }
  return undefined;
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

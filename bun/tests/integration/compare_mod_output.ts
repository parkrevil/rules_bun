// Compares the npm extension's repository set across CI's OSes (FR-011, US2-7,
// quickstart scenario 6; tasks.md T114). Each argument is a directory holding
// the output of `bazel mod show_extension @rules_bun//bun:extensions.bzl%npm`
// as show_extension.txt and of `bazel mod show_repo --all_repos` as
// show_repo.txt, written in e2e/smoke on one OS, or the same two files that
// reproducible_test writes for its inner workspace (tasks.md T131).
//
//   bazel run //bun/tests/integration:compare_mod_output -- <linux> <macos> <windows>
//
// Compared are the show_extension output and the show_repo sections of the
// repositories it lists; other repositories (for example Bazel's C++
// autoconfiguration) may differ by OS. The one normalized line is the usage
// header, which names the MODULE.bazel path of the checkout.

import { readFileSync } from "node:fs";
import { isAbsolute, join } from "node:path";

function lines(text: string): string[] {
  return text.replace(/^﻿/, "").split(/\r?\n/);
}

/** The show_extension output and the show_repo sections of its repositories, normalized. */
export function normalize(extension: string, repos: string): string[] {
  const ext = lines(extension).map((l) => l.replace(/^(## Usage in .* from ).*[\\/](MODULE\.bazel:\d+)$/, "$1$2"));
  const header = /^## @@([^/]*)\/\/[^%]*%(\S+):$/.exec(ext[0] ?? "");
  if (!header) throw new Error(`the show_extension output does not start with an extension header: ${JSON.stringify(ext[0])}`);
  const prefix = `${header[1]}+${header[2]}+`;
  const listed: string[] = [];
  const at = ext.indexOf("Fetched repositories:");
  for (let i = at + 1; at !== -1 && i < ext.length && ext[i].startsWith("  - "); i++) {
    listed.push(ext[i].slice(4).replace(/ \(imported by .*\)$/, ""));
  }
  if (listed.length === 0) throw new Error("the show_extension output lists no fetched repository");

  const sections = new Map<string, string[]>();
  let current: string[] | undefined;
  for (const line of lines(repos)) {
    const name = /^## @@(.*):$/.exec(line);
    if (name) sections.set(name[1], (current = [line]));
    else current?.push(line);
  }
  const out = [...ext];
  for (const repo of listed) {
    const section = sections.get(prefix + repo);
    if (section === undefined) throw new Error(`the show_repo output has no section for @@${prefix}${repo}`);
    out.push(...section);
  }
  return out;
}

/** The first line at which `b` differs from `a`, or undefined. */
export function firstDifference(a: string[], b: string[]): { line: number; a?: string; b?: string } | undefined {
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    if (a[i] !== b[i]) return { line: i + 1, a: a[i], b: b[i] };
  }
  return undefined;
}

if (import.meta.main) {
  const dirs = process.argv.slice(2).map((d) => (isAbsolute(d) ? d : join(process.env.BUILD_WORKING_DIRECTORY ?? process.cwd(), d)));
  if (dirs.length < 2) {
    console.error("usage: compare_mod_output <dir> <dir> [<dir>...]");
    process.exit(2);
  }
  const read = (dir: string) =>
    normalize(readFileSync(join(dir, "show_extension.txt"), "utf8"), readFileSync(join(dir, "show_repo.txt"), "utf8"));
  const first = read(dirs[0]);
  let failed = false;
  for (const dir of dirs.slice(1)) {
    const diff = firstDifference(first, read(dir));
    if (diff) {
      console.error(`compare_mod_output: ${dir} differs from ${dirs[0]} at line ${diff.line}: ${JSON.stringify(diff.b)} instead of ${JSON.stringify(diff.a)}`);
      failed = true;
    }
  }
  if (!failed) console.log(`compare_mod_output: ${dirs.length} outputs are identical (${first.length} lines)`);
  process.exit(failed ? 1 : 0);
}

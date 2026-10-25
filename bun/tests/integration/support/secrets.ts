// FR-020: nothing credential-related enters a repository attribute or a
// generated file. Scans the files of the npm extension's repositories in an
// inner output base and the `bazel mod show_repo` output of `repos`.

import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import type { Inner } from "./inner.ts";

/** Returns where each of `secrets` was found; empty when none was. */
export async function findSecrets(inner: Inner, secrets: string[], repos: string[]): Promise<string[]> {
  const external = join(await inner.outputBase(), "external");
  const found: string[] = [];
  const scan = (path: string) => {
    if (statSync(path).isDirectory()) {
      for (const entry of readdirSync(path)) scan(join(path, entry));
      return;
    }
    const text = readFileSync(path, "latin1");
    for (const secret of secrets) if (text.includes(secret)) found.push(`${path}: ${secret}`);
  };
  for (const entry of readdirSync(external)) {
    if (entry.includes("rules_bun++npm+")) scan(join(external, entry));
  }
  const show = await inner.run(["mod", "show_repo", ...repos.map((r) => `@@rules_bun++npm+${r}`)]);
  if (show.exitCode !== 0) throw new Error(`bazel mod show_repo failed:\n${show.stderr}`);
  for (const secret of secrets) if (show.stdout.includes(secret)) found.push(`bazel mod show_repo: ${secret}`);
  return found;
}

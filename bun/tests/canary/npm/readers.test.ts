// Every bun.lock canary names the reader it protects (feature 006 T108, US4 scenario 1): each
// `<name> in bun/private/<file>.bzl` a canary's source writes names a function, a nested function
// or a constant that file defines, so a failing canary sends the maintainer to code that exists.

import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { rlocation, rlocationList } from "../../support/spawn.ts";

const DIR = "_main/bun/tests/canary/npm";
const MENTION = /(\S+) in (bun\/private\/[a-z_]+\.bzl)/g;

function defines(text: string, name: string): boolean {
  return new RegExp(`^\\s*def ${name}\\(|^${name} = `, "m").test(text);
}

test("every canary's readers are defined where it says (T108)", () => {
  // The canaries of this package only (a test's runfiles may hold another copy below it).
  const canaries = rlocationList(DIR).filter((path) => /^c_[a-z0-9]+\.test\.ts$/.test(path.slice(DIR.length + 1)));
  const problems: string[] = [];
  let checked = 0;
  for (const path of canaries) {
    const name = path.slice(DIR.length + 1);
    const source = readFileSync(rlocation(path), "utf8");
    // c_winname is a Bazel canary, not a bun.lock one: it names no reader.
    if (!source.includes("canaryFail(")) continue;
    const mentions = [...source.matchAll(MENTION)];
    if (mentions.length === 0) problems.push(`${name}: names no reader in bun/private/`);
    for (const [, word, file] of mentions) {
      checked++;
      const reader = word.replace(/^[`"']+|[`"',]+$/g, "");
      let text: string;
      try {
        text = readFileSync(rlocation(`_main/${file}`), "utf8");
      } catch {
        problems.push(`${name}: names ${file}, which this test's data does not hold`);
        continue;
      }
      if (!/^[A-Za-z_]\w*$/.test(reader) || !defines(text, reader)) problems.push(`${name}: "${word} in ${file}" names nothing ${file} defines`);
    }
  }
  expect(checked).toBeGreaterThan(20);
  expect(problems).toEqual([]);
});

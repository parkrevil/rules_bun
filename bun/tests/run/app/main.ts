// A self-checking program: on the first mismatch it prints an English message
// naming the item and exits 1. Run as:
//   bazel run //bun/tests/run/app:main -- extra

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { greet } from "../lib/greet.ts";

function check(item: string, ok: boolean, detail: string): void {
  if (!ok) {
    console.error(`wrong ${item}: ${detail}`);
    process.exit(1);
  }
}

function rlocation(path: string): string {
  const manifest = process.env.RUNFILES_MANIFEST_FILE;
  if (manifest) {
    for (const line of readFileSync(manifest, "utf8").split("\n")) {
      const space = line.indexOf(" ");
      if (line.slice(0, space) === path) return line.slice(space + 1);
    }
    return "";
  }
  const dir = process.env.RUNFILES_DIR ?? "";
  const found = join(dir, path);
  return existsSync(found) ? found : "";
}

const greeting = greet("world");
check("import from another package", greeting === "hello, world", greeting);

const message = readFileSync(join(import.meta.dir, "message.txt"), "utf8");
check("data file next to the entry point", message === "message from app\n", JSON.stringify(message));

const expectedArgs = ["--name=world", "_main/bun/tests/run/app/message.txt", "split", "a b", "extra"];
const args = process.argv.slice(2);
for (let i = 0; i < Math.max(args.length, expectedArgs.length); i++) {
  check(`argument ${i}`, args[i] === expectedArgs[i], `expected ${JSON.stringify(expectedArgs[i])}, got ${JSON.stringify(args[i])}`);
}

const original = rlocation(args[1]);
check(
  "data file through runfiles",
  original !== "" && readFileSync(original, "utf8") === "message from app\n",
  `${args[1]} resolved to ${JSON.stringify(original)}`,
);

check("GREETING", process.env.GREETING === "hello", JSON.stringify(process.env.GREETING));
check("import.meta.main", import.meta.main === true, String(import.meta.main));

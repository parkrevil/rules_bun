// A self-checking program: on the first mismatch it prints an English message
// naming the item and exits 1. Run as:
//   bazel run //app:main

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { greet } from "./greet.ts";

function check(item: string, ok: boolean, detail: string): void {
  if (!ok) {
    console.error(`wrong ${item}: ${detail}`);
    process.exit(1);
  }
}

const greeting = greet("world");
check("import", greeting === "hello, world", greeting);

const message = readFileSync(join(import.meta.dir, "message.txt"), "utf8");
check("data file next to the entry point", message === "message from app\n", JSON.stringify(message));

const args = process.argv.slice(2);
check("arguments", JSON.stringify(args) === JSON.stringify(["--name=world"]), JSON.stringify(args));

check("GREETING", process.env.GREETING === "hello", JSON.stringify(process.env.GREETING));

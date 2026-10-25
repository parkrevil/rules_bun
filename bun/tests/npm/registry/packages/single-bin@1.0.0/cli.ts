// Prints its arguments as JSON; with a first argument --out=<file>, writes the
// remaining arguments as JSON to <file> instead.
import { writeFileSync } from "node:fs";
const args = process.argv.slice(2);
if (args[0]?.startsWith("--out=")) {
  writeFileSync(args[0].slice("--out=".length), JSON.stringify(args.slice(1)));
} else {
  console.log(JSON.stringify(args));
}

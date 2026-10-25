import { readFileSync } from "node:fs";

// Milliseconds from the launcher's start to this program's first line.
const elapsed = Date.now() - Number(readFileSync(process.env.RULES_BUN_LAUNCH_TIMESTAMP!, "utf8"));
console.log(elapsed);

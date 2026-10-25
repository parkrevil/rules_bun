// Loads a package and prints what an undeclared bunfig.toml or .env of the
// working directory would have changed.
import a from "a";

console.log(
  JSON.stringify({
    a: a.version,
    bunfig: (globalThis as Record<string, unknown>).__RULES_BUN_BUNFIG ?? null,
    dotenv: process.env.RULES_BUN_DOTENV ?? null,
  }),
);

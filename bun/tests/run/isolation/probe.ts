// Prints what an undeclared bunfig.toml or .env would have changed.
console.log(
  JSON.stringify({
    bunfig: (globalThis as Record<string, unknown>).__RULES_BUN_BUNFIG ?? null,
    dotenv: process.env.RULES_BUN_DOTENV ?? null,
  }),
);

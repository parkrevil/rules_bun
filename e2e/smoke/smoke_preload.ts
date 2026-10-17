// A fixture declared by no target: bunfig.toml at the module root preloads it.
// If Bun ever read that bunfig.toml, this global would be set (FR-018).
(globalThis as Record<string, unknown>).__RULES_BUN_SMOKE_PRELOAD = "loaded";

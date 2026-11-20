// Corpus projects Bun 1.4.2 cannot write or install, each with the reason (feature 006 US5,
// research R10). bun/tests/npm/registry/write_lockfiles.ts --bun-1-4-2 skips them and
// conformance.test.ts prints them in its 1.4.2 mode. Line numbers are of bun.lock.rs at bun-v1.4.2.
export const NOT_APPLICABLE_1_4_2: Record<string, string> = {};

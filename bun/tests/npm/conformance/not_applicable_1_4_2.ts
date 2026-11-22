// Corpus projects Bun 1.4.2 cannot write or install, each with the reason (feature 006 US5,
// research R10). bun/tests/npm/registry/write_lockfiles.ts --bun-1-4-2 skips them and
// conformance.test.ts prints them in its 1.4.2 mode. Line numbers are of Bun's source at bun-v1.4.2.
export const NOT_APPLICABLE_1_4_2: Record<string, string> = {
  conformance_root_row:
    'Bun 1.4.2 cannot write it: its install of a member depending on the root by "workspace:*" fails with "Workspace dependency \\"conformance-root-row\\" not found"; for "workspace:../.." it writes the lockfile with the root: row, which its own frozen install refuses ("No matching version for workspace dependency", src/install/lockfile/Package.rs L1965) (T171)',
  conformance_override_root_ref:
    'Bun 1.4.2 cannot write it: for b in both "dependencies" and "devDependencies" it writes the packages key "b" twice ("b@file:b2", "b@file:b1"), and its own frozen install refuses that lockfile ("Duplicate package path", src/install/lockfile/bun.lock.rs L3033) (T179)',
};

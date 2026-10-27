"""Workspace glob cases the matcher must answer as Bun 1.4.4 does (research R9).

`glob_compare.test.ts` builds `TREE` under `TEST_TMPDIR`, runs the pinned Bun's
`install --lockfile-only` for each case's `workspaces` patterns and compares the lockfile's
`workspaces` keys with what `glob_members` wrote for the case.
"""

# Directories of the tree; those in MANIFESTS hold a package.json.
TREE = [
    ".hidden",
    ".hidden/h",
    "node_modules",
    "node_modules/zz",
    "other",
    "other/c",
    "packages",
    "packages/.dot",
    "packages/a",
    "packages/a/node_modules",
    "packages/a/node_modules/n",
    "packages/ab",
    "packages/b",
    "packages/deep",
    "packages/deep/x",
    "packages/excluded",
    "packages/nopkg",
    "tools",
    "tools/t1",
    "tools/t22",
]

MANIFESTS = [
    ".hidden/h",
    "node_modules/zz",
    "other/c",
    "packages/.dot",
    "packages/a",
    "packages/a/node_modules/n",
    "packages/ab",
    "packages/b",
    "packages/deep/x",
    "packages/excluded",
    "tools/t1",
    "tools/t22",
]

GLOB_CASES = {
    "star": ["packages/*"],
    "question": ["packages/?"],
    "prefix": ["packages/a*"],
    "globstar": ["packages/**"],
    "globstar_root": ["**"],
    "globstar_leaf": ["**/x"],
    "globstar_zero": ["packages/**/a"],
    "dot_slash": ["./packages/*/"],
    "class": ["packages/[ab]"],
    "range": ["packages/[a-b]"],
    "class_bang": ["packages/[!a]*"],
    "class_caret": ["packages/[^a]*"],
    "braces": ["packages/{a,b}"],
    "braces_paths": ["{packages/ab,tools/t22}"],
    "negation": ["packages/*", "!packages/excluded"],
    "negation_braces": ["packages/*", "!packages/{a,b}"],
    "negation_globstar": ["packages/*", "!**/excluded"],
    "negation_first": ["!packages/excluded", "packages/*"],
    "negation_then_glob": ["packages/*", "!packages/a*", "packages/a*"],
    "negation_globstar_dir": ["**", "!packages/**"],
    "negation_dot_slash": ["packages/*", "!./packages/excluded"],
    "negation_trailing_slash": ["packages/*", "!packages/excluded/"],
    "negation_glob_of_path": ["packages/a", "!packages/*"],
    "negation_then_path": ["packages/*", "!packages/a*", "packages/ab"],
    "negation_of_path": ["packages/a", "packages/b", "!packages/a"],
    "node_modules": ["packages/a/node_modules/*"],
    "explicit_dot": ["packages/.*"],
    "hidden_parent": [".hidden/*"],
    "object_form": {"packages": ["tools/*"]},
}

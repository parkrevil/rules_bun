# Data Model: Upgrade the Pinned Bun to 1.4.4

No new data structure. The entities of the spec map to existing files; this lists their fields,
the rules the upgrade must keep, and the states a canary passes through.

## Known Bun version

`TOOL_VERSIONS` in `bun/private/versions.bzl`: version string → platform → SRI.

| Field | Rule |
|---|---|
| version key | `"1.4.2"` (kept, FR-003) and `"1.4.4"` (added, FR-001) |
| platform keys | exactly `linux-x64`, `linux-aarch64`, `darwin-x64`, `darwin-aarch64`, `windows-x64` |
| integrity | `sha256-<base64>` converted from the release's `SHASUMS256.txt` (research R1) |

Read by `repositories.bzl` when `bun.toolchain` gives no `integrity`; checked by
`versions_test` (both versions present, every platform, SRI form).

## Vendored archive

One per platform: an `http_file` `integration_bun-<platform>.zip` in `MODULE.bazel` (inside the
`update.ts` region) and its loopback path in `archives.bzl`.

| Field | Rule |
|---|---|
| URL / path | `…/oven-sh/bun/releases/download/bun-v1.4.4/bun-<platform>.zip` |
| integrity | equal to `TOOL_VERSIONS["1.4.4"][<platform>]` |
| writer | `bun/tests/integration/registry/update.ts` only (research R4) |

The nine nested workspaces' `bun.toolchain(bun_version = …)` must name the version these archives
hold, or the inner build reaches for a download the loopback server does not serve.

## Canary

A `bun_test` under `bun/tests/canary/` (FR-028) or `bun/tests/canary/npm/` (`bun.lock`).

| Field | Rule |
|---|---|
| ID | C1 … C16, C-* (research R6) |
| pinned behavior | stated in the header comment, naming the pinned Bun version |
| reader or workaround | named in the failure message (`canaryFail` or `MESSAGE`) |
| red mode | `RULES_BUN_CANARY_RED=1` for `bun.lock` canaries; each still fails naming its reader |

State transitions when run against 1.4.4:

```text
run ──pass──> unchanged (header names 1.4.4)
  └──red───> behavior changed
               ├─ reader/workaround still needed ──> updated to the 1.4.4 behavior; canary pins it
               ├─ workaround no longer needed ─────> workaround and canary removed (C-TD, R6)
               └─ needs a new access or design ────> work stops; gap reported (constitution V)
```

Every transition other than "unchanged" is recorded in research Part 3 with its evidence.

## Pinned-Bun fixture

A committed file whose content Bun wrote and tests read as ground truth (research R8).

| Fixture | Writer | Readers |
|---|---|---|
| `bun/tests/run/isolation/registry/*.tgz` | `bun pm pack` | `install.test.ts` |
| `bun/tests/npm/registry/archives/*.tgz` | `pack.ts` | fixture hubs (`npm.replace_package`), loopback registries |
| `bun/tests/npm/fixtures/*/bun.lock` (+ `package.json`, files Bun changed) | `write_lockfiles.ts` | fixture hubs, unit tests, integration tests |
| `bun/tests/npm/scale/{bun.lock,package.json}` | `scale/generate.ts` | `scale_test`, nested `scale` workspace |
| inline lockfiles in `credentials.test.ts`, `registries.test.ts` | `bun install` of 1.4.4 | those tests |
| `e2e/smoke/bun.lock` | `bun install --lockfile-only` of 1.4.4 (re-save) | `e2e/smoke` hub |

Rule: content exactly as Bun 1.4.4 wrote it; only the edits the writer script performs itself.

## Bun-behavior statement

A docstring, `doc =`, diagnostic, comment or example naming a Bun version's behavior (research R9).

| Field | Rule |
|---|---|
| version named | 1.4.4 (FR-004), except the 1.4.2 `TOOL_VERSIONS` entry and non-Bun strings (FR-010) |
| evidence | a canary, a test or an observation against 1.4.4 (research R6, R7) |

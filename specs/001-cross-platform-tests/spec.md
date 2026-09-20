# Feature Specification: Tests that run on every supported platform

**Feature Branch**: `001-cross-platform-tests`

**Created**: 2026-09-20

**Status**: Draft

**Input**: User description: "CI must pass on every platform rules_bun claims to support, and the ruleset must obey its own constitution. Three concrete gaps: the e2e smoke module declares no test target, the hardening test ships a shell launcher Windows cannot run, and the repository rules guard `repository_ctx.repo_metadata` with a fallback for Bazel versions older than the declared minimum."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A consumer's platform is covered by the smoke check (Priority: P1)

Someone adopting rules_bun — or the Bazel Central Registry checking it before publishing a release
— runs the test command on the consumer module that uses rules_bun the way a real project does.
They expect that command to run a check and report a result.

**Why this priority**: The command currently reports an error instead of a result, on every
platform. The registry's presubmit asks for the same command, so this blocks publication as well as
local verification.

**Independent Test**: Run the test command in the consumer module on one platform. It reports at
least one executed check, and the result is a pass.

**Acceptance Scenarios**:

1. **Given** a clean checkout, **When** the test command runs in the consumer module, **Then** at
   least one check executes and the command reports success.
2. **Given** the registry presubmit configuration, **When** it asks the consumer module for its
   tests, **Then** the requested tests exist.
3. **Given** a toolchain that fails to resolve or a Bun binary that cannot run, **When** the check
   runs, **Then** it fails rather than reporting success.

---

### User Story 2 - The hardening guarantee is checked on every supported platform (Priority: P2)

A maintainer changes how Bun is invoked. They expect the check that protects users from a hostile
`bunfig.toml` preload or `.env` in the working directory to run everywhere the ruleset is supported,
including Windows, and to fail if the protection is lost.

**Why this priority**: The guarantee is already checked on Linux and macOS; Windows is the gap. The
check reports an infrastructure error there today, which both hides the guarantee and fails CI.

**Independent Test**: Run the root test command on Windows. The hardening check executes and
passes; weaken a hardening flag and it fails.

**Acceptance Scenarios**:

1. **Given** any supported platform, **When** the root test command runs, **Then** the hardening
   check executes and passes.
2. **Given** the hardening protection is removed or weakened, **When** the check runs, **Then** it
   fails and names what leaked.
3. **Given** the environment the check builds, **When** the protection is absent, **Then** the
   hostile preload and `.env` are demonstrably loaded — the check cannot pass by failing to
   reproduce the attack.

---

### User Story 3 - The ruleset carries no fallback for unsupported Bazel versions (Priority: P3)

A maintainer reading the repository rules sees only code that the declared minimum Bazel version
supports, with no branch for versions the ruleset does not accept.

**Why this priority**: It is dead code rather than a failure, but it misleads readers about which
Bazel versions are supported and it violates the constitution.

**Independent Test**: Search the repository rules for capability checks of APIs the declared
minimum Bazel provides; there are none, and fetching a toolchain still works.

**Acceptance Scenarios**:

1. **Given** the declared minimum Bazel version, **When** a toolchain repository is fetched,
   **Then** it reports its reproducibility metadata without any capability check.

---

### Edge Cases

- Windows has no Bash, so no check may require one; a launcher that picks a per-platform
  interpreter is fine.
- The hardening check must place the hostile files where the Bun process actually reads them; if it
  does not, the check would pass without testing anything.
- Test output that differs per platform (line endings, path separators) must not change the
  verdict.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The consumer module MUST declare at least one test that exercises the registered Bun
  toolchain, so that its test command executes a check on every supported platform.
- **FR-002**: The registry presubmit configuration MUST match the tests the consumer module
  declares.
- **FR-003**: The hardening check MUST run on every supported platform without requiring a shell.
- **FR-004**: The hardening check MUST keep failing whenever a `bunfig.toml` preload executes or a
  `.env` file is read in the Bun process's working directory.
- **FR-005**: The hardening check MUST be demonstrably non-vacuous: with the protection absent, the
  same setup MUST show the preload and `.env` taking effect.
- **FR-006**: The repository rules MUST NOT branch on the availability of APIs that every Bazel
  version allowed by the declared compatibility provides.
- **FR-007**: The public API, the pinned Bun version, and the set of hardening flags MUST remain
  unchanged.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All six CI test jobs (three operating systems × root and consumer module) report
  success, where four fail today.
- **SC-002**: The test command in the consumer module executes at least one check and exits
  successfully; it no longer exits with "no test targets".
- **SC-003**: The hardening check passes on all three operating systems, and on the platform where
  the experiment is run, removing a hardening flag makes it fail.
- **SC-004**: No capability check for a declared-minimum Bazel API remains in the repository rules.
- **SC-005**: No test in the repository supplies its own launcher; whatever shell a test launcher
  uses is chosen by the testing ruleset per platform, so Windows needs no shell interpreter.

## Assumptions

- Supported platforms are the ones CI runs: Linux x86_64, macOS arm64, and Windows x86_64, plus the
  registry presubmit's platform list.
- The declared minimum Bazel version stays 9.2.0 and the pinned Bun version stays 1.4.2.
- The consumer module keeps declaring the lowest dependency versions the ruleset works with, so any
  dependency it gains for testing must not raise them.
- Cross-platform build coverage for the remaining Bun platforms (Linux arm64, macOS x86_64) stays
  analysis-level, as today; no runtime execution is claimed for them.

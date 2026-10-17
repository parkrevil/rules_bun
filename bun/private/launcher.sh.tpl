#!/usr/bin/env bash

# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo>&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v3 ---

# The Linux and macOS launcher of a bun_binary or bun_test (FR-001): it finds the
# target platform's Bun, the rule's configuration file, the static JavaScript
# launcher and the target's launch configuration with the Bash runfiles library,
# and execs Bun on them with the arguments it was given.

set +e # each lookup is checked below

# Bun prepends BUN_OPTIONS to the arguments of every Bun process, so it could run
# code before launcher.js checks it.
if [[ -n "${BUN_OPTIONS+set}" ]]; then
  echo >&2 "rules_bun: BUN_OPTIONS is set; bun_binary and bun_test take Bun options only from their rule (FR-018a)"
  exit 1
fi

# Prints the path of the runfile with the rlocation path $1, or an error naming it.
function runfile() {
  local path
  path="$(rlocation "$1")"
  if [[ -z "$path" || ! -f "$path" ]]; then
    echo >&2 "ERROR: $1 is not in the runfiles"
    return 1
  fi
  echo "$path"
}

bun="$(runfile %bun%)" || exit 1
bunfig="$(runfile %bunfig%)" || exit 1
launcher="$(runfile %launcher%)" || exit 1
launch_config="$(runfile %launch_config%)" || exit 1

# launcher.js and the program find their files through these variables.
runfiles_export_envvars
# runfiles_export_envvars passes a relative path on unchanged, and the second Bun
# process of a bun_test runs in another working directory.
if [[ -n "${RUNFILES_DIR:-}" && "$RUNFILES_DIR" != /* ]]; then
  export RUNFILES_DIR="$PWD/$RUNFILES_DIR"
fi
if [[ -n "${RUNFILES_MANIFEST_FILE:-}" && "$RUNFILES_MANIFEST_FILE" != /* ]]; then
  export RUNFILES_MANIFEST_FILE="$PWD/$RUNFILES_MANIFEST_FILE"
fi

# No transpiler-cache entry for the launcher itself (FR-018); the second process
# gets the same setting from launcher.js.
export BUN_RUNTIME_TRANSPILER_CACHE_PATH=0

exec "$bun" "--config=$bunfig" --no-env-file "$launcher" "$launch_config" "$@"

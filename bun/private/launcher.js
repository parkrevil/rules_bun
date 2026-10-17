// Launcher and load guard of bun_binary and bun_test. The target's executable
// (the shell launcher on Linux and macOS, the hermetic-launcher stub on Windows)
// starts Bun on this file with the target's launch configuration; as the main
// module this file starts the program or `bun test` in a second Bun process,
// which preloads this file again as the load guard (research R13).

import {
  closeSync,
  existsSync,
  mkdtempSync,
  openSync,
  readFileSync,
  realpathSync,
  writeFileSync,
} from "node:fs";
import os from "node:os";
import { isAbsolute, join, normalize, sep } from "node:path";

// The bun_test arguments that may reach `bun test` (research R8 "Arguments").
// <n> is a decimal integer, <value> is not empty.
const ALLOWED_TEST_ARGUMENTS = [
  ["--timeout=<n>", /^--timeout=\d+$/],
  ["--rerun-each=<n>", /^--rerun-each=\d+$/],
  ["--retry=<n>", /^--retry=\d+$/],
  ["--concurrent", /^--concurrent$/],
  ["--randomize", /^--randomize$/],
  ["--seed=<n>", /^--seed=\d+$/],
  ["--bail", /^--bail$/],
  ["--bail=<n>", /^--bail=\d+$/],
  ["--max-concurrency=<n>", /^--max-concurrency=\d+$/],
  ["--todo", /^--todo$/],
  ["--isolate", /^--isolate$/],
  ["--smol", /^--smol$/],
  ["--conditions=<value>", /^--conditions=.+$/s],
  ["--prefer-offline", /^--prefer-offline$/],
  ["--frozen-lockfile", /^--frozen-lockfile$/],
];

// CreateProcessW limits a command line to 32,767 characters, including the
// terminating null (WIN-create); the launcher applies the limit on every OS.
const MAX_COMMAND_LINE = 32767;

// Quotes an argument as the Microsoft C runtime parses it (WIN-argv).
function quoteWindowsArgument(arg) {
  if (arg !== "" && !/[ \t\n\v"]/.test(arg)) return arg;
  let quoted = '"';
  let backslashes = 0;
  for (const ch of arg) {
    if (ch === "\\") {
      backslashes++;
      continue;
    }
    quoted += ch === '"' ? "\\".repeat(2 * backslashes + 1) + ch : "\\".repeat(backslashes) + ch;
    backslashes = 0;
  }
  return quoted + "\\".repeat(2 * backslashes) + '"';
}

// The length, in UTF-16 code units, of the command line the running OS builds
// from `args`, with the terminating null.
function commandLineLength(args) {
  const parts = process.platform === "win32" ? args.map(quoteWindowsArgument) : args;
  return parts.join(" ").length + 1;
}

// The longest guard pattern Bun 1.4.2 compiles, in characters (research R13;
// canary C13).
const MAX_GUARD_PATTERN = 1048576;

function fail(message) {
  console.error(`rules_bun: ${message}`);
  process.exit(1);
}

// Returns a function resolving an rlocation path; `error` is called with an
// English message when a path or the runfiles cannot be found.
function runfilesResolver(error = fail) {
  const manifest = process.env.RUNFILES_MANIFEST_FILE;
  if (manifest) {
    const entries = new Map();
    for (const line of readFileSync(manifest, "utf8").split("\n")) {
      if (line === "") continue;
      if (line.startsWith(" ")) {
        // An escaped line (Bazel's SourceManifestAction; rules_python runfiles.py).
        const rest = line.slice(1);
        const space = rest.indexOf(" ");
        const link = rest.slice(0, space).replaceAll("\\s", " ").replaceAll("\\n", "\n").replaceAll("\\b", "\\");
        const target = rest.slice(space + 1).replaceAll("\\n", "\n").replaceAll("\\b", "\\");
        entries.set(link, target);
      } else {
        const space = line.indexOf(" ");
        entries.set(line.slice(0, space), line.slice(space + 1));
      }
    }
    return (path) => {
      const found = entries.get(path);
      if (found === undefined) error(`${path} is not in the runfiles manifest ${manifest}`);
      return found;
    };
  }
  const dir = process.env.RUNFILES_DIR;
  if (dir) {
    return (path) => {
      const found = join(dir, path);
      if (!existsSync(found)) error(`${path} is not in the runfiles directory ${dir}`);
      return found;
    };
  }
  error("neither RUNFILES_MANIFEST_FILE nor RUNFILES_DIR is set");
}

// Rewrites Bun's LCOV report for Bazel (research R8, G7, G15). Each SF: value is
// read joined to the second process's working directory and, when absolute, as
// itself; a record naming this file is removed, and a record naming exactly one
// declared copy is rewritten to that copy's original File.path. A record naming
// no declared copy or several fails the test without a report.
function rewriteCoverage(config, rlocation, lcov, cwd) {
  const self = normalize(realpathSync(import.meta.path));
  const originals = new Map();
  for (const [copy, original] of config.copies) {
    originals.set(normalize(realpathSync(rlocation(copy))), original);
  }
  const root = realpathSync(cwd);

  const records = [];
  let record = [];
  for (const line of readFileSync(lcov, "utf8").split("\n")) {
    if (line === "") continue;
    record.push(line);
    if (line === "end_of_record") {
      records.push(record);
      record = [];
    }
  }

  const out = [];
  for (const lines of records) {
    const index = lines.findIndex((l) => l.startsWith("SF:"));
    if (index === -1) continue;
    const value = lines[index].slice(3);
    const readings = [normalize(join(root, value))];
    if (isAbsolute(value)) readings.push(normalize(value));
    if (readings.includes(self)) continue;
    const matches = [...new Set(readings.filter((r) => originals.has(r)))];
    if (matches.length === 0) {
      fail(`${config.label}: coverage record SF:${value} names no declared file`);
    }
    if (matches.length > 1) {
      fail(`${config.label}: coverage record SF:${value} names several declared files`);
    }
    lines[index] = `SF:${originals.get(matches[0])}`;
    out.push(...lines);
  }
  return out.length ? out.join("\n") + "\n" : "";
}

// The root of the copy tree: the real path of the first test file's copy with
// its tree path removed. It holds no file, because every tree path begins with a
// repository directory.
function copyTreeRoot(config, rlocation) {
  const [copy, tree] = config.tests[0];
  const real = realpathSync(rlocation(copy));
  const suffix = sep + normalize(tree);
  if (!real.endsWith(suffix)) fail(`${config.label}: the copy ${real} does not end with its tree path ${tree}`);
  return real.slice(0, -suffix.length);
}

async function main() {
  if (process.env.BUN_OPTIONS !== undefined) {
    fail("BUN_OPTIONS is set; bun_binary and bun_test take Bun options only from their rule (FR-018a)");
  }
  const rlocation = runfilesResolver();
  const config = JSON.parse(readFileSync(process.argv[2], "utf8"));
  const userArgs = process.argv.slice(3);
  const guardPreload = `--preload=${realpathSync(import.meta.path)}`;
  const pattern = guardPattern(config.copies.map(([copy]) => realpathSync(rlocation(copy))));
  if (pattern.length > MAX_GUARD_PATTERN) {
    fail(
      `${config.label}: the load guard pattern for ${config.copies.length} declared files is ` +
        `${pattern.length} characters long, over the limit of ${MAX_GUARD_PATTERN} (Bun 1.4.2)`,
    );
  }

  let argv;
  let cwd = process.cwd();
  let coverageDir;
  if (config.mode === "binary") {
    if (userArgs[0] === "--") {
      fail(
        `${config.label}: "--" as the first program argument is not supported, ` +
          'because Bun 1.4.2 drops a "--" directly after the entry point',
      );
    }
    argv = [
      `--config=${realpathSync(rlocation(config.bunfig))}`,
      "--no-env-file",
      "--no-install",
      guardPreload,
      realpathSync(rlocation(config.entry_point)),
      ...userArgs,
    ];
  } else {
    for (const arg of userArgs) {
      if (!ALLOWED_TEST_ARGUMENTS.some(([, pattern]) => pattern.test(arg))) {
        fail(
          `${config.label}: bun_test argument ${JSON.stringify(arg)} is not allowed; ` +
            `allowed forms: ${ALLOWED_TEST_ARGUMENTS.map(([form]) => form).join(", ")}`,
        );
      }
    }
    if (process.env.TESTBRIDGE_TEST_ONLY && Number(process.env.TEST_TOTAL_SHARDS) > 1) {
      fail(`${config.label}: filtering a sharded bun_test is not supported; run it without --test_filter`);
    }
    const protocol = [];
    if (process.env.COVERAGE_DIR) {
      coverageDir = mkdtempSync(join(process.env.TEST_TMPDIR ?? os.tmpdir(), "bun-coverage-"));
      protocol.push("--coverage", "--coverage-reporter=lcov", `--coverage-dir=${coverageDir}`);
    }
    if (process.env.TEST_SHARD_STATUS_FILE) {
      closeSync(openSync(process.env.TEST_SHARD_STATUS_FILE, "a"));
    }
    if (process.env.TEST_TOTAL_SHARDS) {
      const index = Number(process.env.TEST_SHARD_INDEX);
      protocol.push(`--shard=${index + 1}/${process.env.TEST_TOTAL_SHARDS}`);
    }
    if (process.env.TESTBRIDGE_TEST_ONLY) {
      protocol.push(`--test-name-pattern=${process.env.TESTBRIDGE_TEST_ONLY}`);
    }
    if (process.env.XML_OUTPUT_FILE) {
      protocol.push("--reporter=junit", `--reporter-outfile=${process.env.XML_OUTPUT_FILE}`);
    }
    const preloads = config.preload.map((p) => `--preload=${realpathSync(rlocation(p))}`);
    cwd = copyTreeRoot(config, rlocation);
    argv = ["test", guardPreload, ...protocol, ...preloads, ...userArgs, ...config.tests.map(([, tree]) => `./${tree}`)];
  }

  const length = commandLineLength([process.execPath, ...argv]);
  if (length > MAX_COMMAND_LINE) {
    fail(
      `${config.label}: the command line of the second Bun process is ${length} characters long, ` +
        `over the limit of ${MAX_COMMAND_LINE}`,
    );
  }
  const env = {
    ...process.env,
    BUN_RUNTIME_TRANSPILER_CACHE_PATH: "0",
    RULES_BUN_LAUNCH_CONFIG: realpathSync(process.argv[2]),
  };
  delete env.BUN_OPTIONS;
  const child = Bun.spawn([process.execPath, ...argv], {
    cwd,
    env,
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  });
  const exitCode = await child.exited;
  if (coverageDir !== undefined) {
    const lcov = join(coverageDir, "lcov.info");
    const report = existsSync(lcov) ? rewriteCoverage(config, rlocation, lcov, cwd) : "";
    writeFileSync(join(process.env.COVERAGE_DIR, `bunlcov_${crypto.randomUUID()}.dat`), report);
  }
  if (child.signalCode !== null) {
    process.exit(128 + os.constants.signals[child.signalCode]);
  }
  process.exit(exitCode);
}

function escapeRegExp(text) {
  return text.replace(/[\\^$.*+?()[\]{}|/]/g, "\\$&");
}

// A regular expression matching exactly `paths`, as a prefix trie: each
// character escaped, shared prefixes emitted once, branches as non-capturing
// groups (research R13).
function prefixTrie(paths) {
  const root = new Map();
  for (const path of paths) {
    let node = root;
    for (const ch of path) {
      if (!node.has(ch)) node.set(ch, new Map());
      node = node.get(ch);
    }
    node.set("", null);
  }
  const emit = (node) => {
    const branches = [];
    for (const [ch, child] of node) {
      if (ch !== "") branches.push(escapeRegExp(ch) + emit(child));
    }
    if (branches.length === 0) return "";
    if (node.has("")) return `(?:${branches.join("|")})?`;
    return branches.length === 1 ? branches[0] : `(?:${branches.join("|")})`;
  };
  return emit(root);
}

// The guard's filter: any path except the declared ones.
function guardPattern(paths) {
  // [\s\S] rather than ".": a path may hold line terminators, which "." does not match.
  return `^(?!(?:${prefixTrie(paths)})$)[\\s\\S]*$`;
}

function registerGuard(filter, reject) {
  Bun.plugin({
    name: "rules_bun load guard",
    setup(build) {
      build.onLoad({ filter, namespace: "file" }, (args) => {
        throw new Error(reject(args.path));
      });
    },
  });
}

// The declared real paths of the target, read from the file named by
// RULES_BUN_LAUNCH_CONFIG, or the reason they cannot be read.
function declaredFiles() {
  const file = process.env.RULES_BUN_LAUNCH_CONFIG;
  if (file === undefined) return { reason: "RULES_BUN_LAUNCH_CONFIG is not set" };
  let config;
  try {
    config = JSON.parse(readFileSync(file, "utf8"));
  } catch (error) {
    return { reason: `cannot read the launch configuration ${file}: ${error.message}` };
  }
  let paths;
  try {
    const rlocation = runfilesResolver((message) => {
      throw new Error(message);
    });
    paths = config.copies.map(([copy]) => realpathSync(rlocation(copy)));
  } catch (error) {
    return { reason: `cannot resolve the declared files: ${error.message}` };
  }
  return { label: config.label, paths };
}

// The load guard: rejects every module of the "file" namespace whose path is not
// the real path of a declared copy (research R13). When the declared files
// cannot be read, it rejects every module (fail closed).
function guard() {
  const declared = declaredFiles();
  if (declared.reason !== undefined) {
    // `bun test` prints no error when the guard rejects the test file itself.
    console.error(`rules_bun load guard: ${declared.reason}; every module is rejected`);
    registerGuard(/.*/, (path) => `rules_bun load guard: ${declared.reason}; ${path} is rejected`);
    return;
  }
  const filter = new RegExp(guardPattern(declared.paths));
  registerGuard(filter, (path) => `${declared.label}: ${path} is not declared by this target`);
}

if (import.meta.main) {
  await main();
} else {
  guard();
}

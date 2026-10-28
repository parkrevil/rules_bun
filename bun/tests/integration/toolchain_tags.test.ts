// bun.toolchain across modules (FR-015, FR-016, research R8): the root
// module's integrity wins per platform, two non-root modules that disagree fail
// evaluation naming both, integrity keys and values and bun_version are
// validated naming the module, and several tags of one version are merged per
// platform. Each case writes the root's and the two dependencies' MODULE.bazel.

import { afterAll, expect, test } from "bun:test";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";

const inner = new Inner("toolchain_tags");
afterAll(() => inner.close());

// The archive the inner build fetches is the host's.
const HOST = `${process.platform === "win32" ? "windows" : process.platform}-${process.arch === "arm64" ? "aarch64" : "x64"}`;
// bun/private/versions.bzl, Bun 1.4.4.
const KNOWN: Record<string, string> = {
  "linux-x64": "sha256-v4zL+ysLgBWeD5ptFcVTF63YB3U028YTCj7bUvzLOVw=",
  "linux-aarch64": "sha256-uqa7NvUdblhWHgK76oJQOKnfRU9nPW13bou/hvjHhQ4=",
  "darwin-x64": "sha256-UKNJH3Orwv6BZzFxqFdi07wswWgMzsrdmD3pmt93l34=",
  "darwin-aarch64": "sha256-wkDX8My5DCY6hJ/NsJt+5iYw2SE0jtaq/ahrnVd7xRA=",
  "windows-x64": "sha256-zSwPzMePPt4fUMqCehXwY+2hPU0VCj0GdPT24yPYZKU=",
};
const CORRECT = KNOWN[HOST];
const WRONG = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
const OTHER = HOST === "windows-x64" ? "linux-x64" : "windows-x64";
const KEYS = "darwin-aarch64, darwin-x64, linux-aarch64, linux-aarch64-musl, linux-x64, linux-x64-musl, windows-x64";

const tag = (version: string, integrity: Record<string, string> = {}) =>
  `bun.toolchain(\n    bun_version = "${version}",\n    integrity = ${JSON.stringify(integrity)},\n)\n`;

function modules(root: string[], depA: string[] = [], depB: string[] = [], useRepos: string[] = []) {
  const ext = 'bun = use_extension("@rules_bun//bun:extensions.bzl", "bun")\n';
  const deps = ["a", "b"]
    .map((d) => `bazel_dep(name = "dep_${d}", version = "1.0.0")\nlocal_path_override(\n    module_name = "dep_${d}",\n    path = "dep_${d}",\n)\n`)
    .join("");
  inner.write(
    "MODULE.bazel",
    `bazel_dep(name = "rules_bun")\n${deps}\n${ext}${root.join("")}use_repo(bun, ${["bun_toolchains", ...useRepos].map((r) => `"${r}"`).join(", ")})\n\nregister_toolchains("@bun_toolchains//:all")\n`,
  );
  for (const [d, tags] of [["a", depA], ["b", depB]] as const) {
    inner.write(
      `dep_${d}/MODULE.bazel`,
      `module(\n    name = "dep_${d}",\n    version = "1.0.0",\n)\n\nbazel_dep(name = "rules_bun")\n\n${tags.length ? ext + tags.join("") : ""}`,
    );
  }
}

const errorLine = (stderr: string) => stderr.split("\n").find((l) => l.startsWith("Error in fail:")) ?? stderr;

// A changed integrity changes the Bun repository's attributes, so it is fetched
// again; the repository cache answers only a request for the same digest.
const build = () => inner.run(["build", "//:main"]);

test(
  "(a) the root's integrity wins over a dependency's",
  async () => {
    modules([tag("1.4.4", { [HOST]: CORRECT })], [tag("1.4.4", { [HOST]: WRONG })]);
    const result = await build();
    expect(result.exitCode, result.stderr).toBe(0);
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "(a2) the root's wrong integrity is used, not ignored",
  async () => {
    modules([tag("1.4.4", { [HOST]: WRONG })], [tag("1.4.4", { [HOST]: CORRECT })]);
    const result = await build();
    expect(result.exitCode).not.toBe(0);
    expect(result.stderr).toContain("Checksum");
  },
  INNER_TIMEOUT,
);

test(
  "(b) two dependencies with different integrity for one platform fail evaluation naming both",
  async () => {
    modules([tag("1.4.4")], [tag("1.4.4", { [HOST]: CORRECT })], [tag("1.4.4", { [HOST]: WRONG })]);
    const result = await inner.run(["build", "//:main"]);
    console.log(errorLine(result.stderr));
    expect(result.exitCode).not.toBe(0);
    for (const text of ["dep_a@", "dep_b@", "1.4.4", HOST]) expect(errorLine(result.stderr)).toContain(text);
  },
  INNER_TIMEOUT,
);

test(
  "(c) an unknown integrity key fails evaluation naming the module, the key and the known keys",
  async () => {
    modules([tag("1.4.4", { linux_x64: CORRECT })]);
    const result = await inner.run(["build", "//:main"]);
    console.log(errorLine(result.stderr));
    expect(result.exitCode).not.toBe(0);
    for (const text of ["the root module", '"linux_x64"', KEYS]) expect(errorLine(result.stderr)).toContain(text);
  },
  INNER_TIMEOUT,
);

test(
  "(d) an integrity value that is no SRI fails evaluation naming the module, the key and the forms",
  async () => {
    modules([], [tag("1.4.4", { [HOST]: "abc" })]);
    const result = await inner.run(["build", "//:main"]);
    console.log(errorLine(result.stderr));
    expect(result.exitCode).not.toBe(0);
    for (const text of ["dep_a@", `"${HOST}"`, "sha256-", "sha384-", "sha512-"]) expect(errorLine(result.stderr)).toContain(text);
  },
  INNER_TIMEOUT,
);

test(
  "(e) two root tags of one version are merged per platform",
  async () => {
    // The first tag's wrong value for the host stays in effect after the second tag.
    modules([tag("1.4.4", { [HOST]: WRONG }), tag("1.4.4", { [OTHER]: KNOWN[OTHER] })]);
    const result = await build();
    expect(result.exitCode).not.toBe(0);
    expect(result.stderr).toContain("Checksum");
  },
  INNER_TIMEOUT,
);

test(
  "(e2) two root tags with different integrity for one platform fail evaluation",
  async () => {
    modules([tag("1.4.4", { [HOST]: CORRECT }), tag("1.4.4", { [HOST]: WRONG })]);
    const result = await inner.run(["build", "//:main"]);
    console.log(errorLine(result.stderr));
    expect(result.exitCode).not.toBe(0);
    for (const text of ["the root module", "1.4.4", HOST]) expect(errorLine(result.stderr)).toContain(text);
  },
  INNER_TIMEOUT,
);

test(
  "(e3) two dependencies that agree supply the integrity",
  async () => {
    modules([tag("1.4.4")], [tag("1.4.4", { [HOST]: CORRECT })], [tag("1.4.4", { [HOST]: CORRECT })]);
    const result = await build();
    expect(result.exitCode, result.stderr).toBe(0);
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "(f) a bun_version that is no version fails evaluation naming the module",
  async () => {
    modules([], [tag("x")]);
    const result = await inner.run(["build", "//:main"]);
    console.log(errorLine(result.stderr));
    expect(result.exitCode).not.toBe(0);
    for (const text of ["dep_a@", '"x"']) expect(errorLine(result.stderr)).toContain(text);
  },
  INNER_TIMEOUT,
);

test(
  "(g) an unknown version with glibc integrity only fails a musl fetch naming the musl key",
  async () => {
    const glibc = { "linux-x64": WRONG, "linux-aarch64": WRONG, "darwin-x64": WRONG, "darwin-aarch64": WRONG, "windows-x64": WRONG };
    modules([tag("9.9.9", glibc)], [], [], ["bun_linux-x64", "bun_linux-x64-musl"]);
    const musl = await inner.run(["fetch", "@bun_linux-x64-musl//..."]);
    console.log(errorLine(musl.stderr));
    expect(musl.exitCode).not.toBe(0);
    for (const text of ["does not know the integrity of Bun 9.9.9", '"linux-x64-musl": "sha256-..."']) expect(musl.stderr).toContain(text);
    // The glibc repository has the integrity it was given: its download is attempted.
    const fetched = await inner.run(["fetch", "@bun_linux-x64//..."]);
    expect(fetched.exitCode).not.toBe(0);
    expect(fetched.stderr).not.toContain("does not know the integrity");
  },
  INNER_TIMEOUT,
);

// Package executables (FR-018, US6-5, contracts/public-api.md naming rule):
// executables declared only through directories.bin get no target, and two
// bin entries whose names become one target name fail evaluation naming both.
// A bin that is a JavaScript program for Node or Bun by its #! line runs with
// the toolchain's Bun; any other fails analysis naming the reason; `bazel build
// //...` builds no bin target (feature 005 FR-012, research D1). A bin of a package that depends on
// a workspace member links the member as Bun links it, and needs the member visible to the package
// that calls npm_link_all_packages() (feature 006 BC-4), also a member reached through another
// member's packages (T123), and through a member's `workspace:` link and more than one further
// member (T131), each only on the platforms where the package linking it is installed (T181).

import { afterAll, expect, test } from "bun:test";
import { existsSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { rlocation } from "../support/spawn.ts";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";

const FIXTURES = "_main/bun/tests/npm/fixtures";
const archive = (p: string) => rlocation(`_main/bun/tests/npm/registry/archives/${p}.tgz`);
const inner = new Inner("bins", {
  npmArchives: [
    archive("node-bin@1.0.0"), archive("single-bin@1.0.0"), archive("dirbin@1.0.0"), archive("member-user@1.0.0"), archive("b@2.0.0"),
    archive("chain-cli@1.0.0"), archive("chain-helper@1.0.0"), archive("mplat-cli@1.0.0"), archive("mplat-helper@1.0.0"),
  ],
});
afterAll(() => inner.close());

// A fixture file, with the loopback port of the run that wrote it replaced.
const fixture = (path: string) =>
  readFileSync(rlocation(`${FIXTURES}/${path}`), "utf8").replaceAll(/http:\/\/127\.0\.0\.1:\d+/g, inner.registry.url);

function project(name: string) {
  inner.write("package.json", fixture(`${name}/package.json`));
  inner.write("bun.lock", fixture(`${name}/bun.lock`));
}

const errorLine = (stderr: string) => stderr.split("\n").find((l) => l.startsWith("Error in fail:")) ?? stderr;

test(
  "directories.bin gives no target",
  async () => {
    project("bins_dirbin");
    const result = await inner.run(["query", "//..."]);
    expect(result.exitCode, result.stderr).toBe(0);
    expect(result.stdout).toContain("//:node_modules/dirbin\n");
    expect(result.stdout).toContain("//:node_modules/single-bin/bin/single-bin\n");
    expect(result.stdout).not.toContain("//:node_modules/dirbin/bin/");
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "two bin names that become one target name fail evaluation naming both",
  async () => {
    project("bins_clash");
    const result = await inner.run(["query", "//..."]);
    console.log(errorLine(result.stderr));
    expect(result.exitCode).not.toBe(0);
    for (const part of ["clash-bin@1.0.0", '"a b"', '"a:b"', '"a_b"']) {
      expect(errorLine(result.stderr)).toContain(part);
    }
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "FR-012: an extensionless bin whose #! line names node runs with the toolchain's Bun",
  async () => {
    project("bins_node");
    for (const bin of ["tsc", "envs", "abs", "bunbin"]) {
      const result = await inner.run(["run", `//:node_modules/node-bin/bin/${bin}`, "--", "x", "--", "y"]);
      expect(result.exitCode, result.stderr).toBe(0);
      expect(result.stdout.trim()).toBe("tsc x -- y");
    }
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "FR-012: a bin file the package repository renames is read through its safe name and runs",
  async () => {
    project("bins_node");
    const result = await inner.run(["run", "//:node_modules/node-bin/bin/build", "--", "x", "--", "y"]);
    expect(result.exitCode, result.stderr).toBe(0);
    expect(result.stdout.trim()).toBe("build x -- y");
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "FR-012: a #!/bin/sh bin fails analysis naming the reason",
  async () => {
    project("bins_node");
    const result = await inner.run(["build", "//:node_modules/node-bin/bin/sh"]);
    console.log(errorLine(result.stderr));
    expect(result.exitCode).not.toBe(0);
    expect(errorLine(result.stderr)).toContain(
      'the bin entry "sh" of the npm package node-bin@1.0.0 is the file bin/sh, which is not a JavaScript program for Node or Bun: it has none of the extensions',
    );
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "research D1: bazel build //... builds no bin target",
  async () => {
    project("bins_dirbin");
    const result = await inner.run(["build", "//..."]);
    expect(result.exitCode, result.stderr).toBe(0);
    const bin = (await inner.run(["info", "bazel-bin"])).stdout.trim();
    // single-bin/bin/single-bin is a .js file; no earlier case builds it.
    expect(existsSync(join(bin, "_npm_bin", "single-bin"))).toBe(false);
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "BC-4: a bin of a package that depends on a workspace member loads the member",
  async () => {
    project("conformance_registry_to_workspace");
    for (const file of ["package.json", "index.js"]) {
      inner.write(`packages/member-lib/${file}`, fixture(`conformance_registry_to_workspace/packages/member-lib/${file}`));
    }
    inner.write(
      "packages/member-lib/BUILD.bazel",
      'load("@rules_bun//bun:defs.bzl", "bun_library")\n\nbun_library(\n    name = "pkg",\n    srcs = ["index.js"],\n    data = ["package.json"],\n    visibility = ["//visibility:public"],\n)\n',
    );
    const result = await inner.run(["run", "//:node_modules/member-user/bin/member-user"]);
    expect(result.exitCode, result.stderr).toBe(0);
    expect(result.stdout.trim()).toBe("member-user member-lib");
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "BC-4: a bin whose member is not visible to the linking package fails with Bazel's visibility error",
  async () => {
    project("conformance_registry_to_workspace");
    for (const file of ["package.json", "index.js"]) {
      inner.write(`packages/member-lib/${file}`, fixture(`conformance_registry_to_workspace/packages/member-lib/${file}`));
    }
    // The member at the default visibility, its own package only (bazel.build concepts/visibility).
    inner.write(
      "packages/member-lib/BUILD.bazel",
      'load("@rules_bun//bun:defs.bzl", "bun_library")\n\nbun_library(\n    name = "pkg",\n    srcs = ["index.js"],\n    data = ["package.json"],\n)\n',
    );
    const result = await inner.run(["build", "//:node_modules/member-user/bin/member-user"]);
    console.log(result.stderr.split("\n").find((line) => line.includes("visib")));
    expect(result.exitCode).not.toBe(0);
    expect(result.stderr).toContain("target '//packages/member-lib:pkg' is not visible from");
    expect(result.stderr).toContain("target '//:node_modules/member-user/bin/member-user'");

    // Visible to the package that calls npm_link_all_packages(), the bin runs.
    inner.write(
      "packages/member-lib/BUILD.bazel",
      'load("@rules_bun//bun:defs.bzl", "bun_library")\n\nbun_library(\n    name = "pkg",\n    srcs = ["index.js"],\n    data = ["package.json"],\n    visibility = ["//:__pkg__"],\n)\n',
    );
    const visible = await inner.run(["run", "//:node_modules/member-user/bin/member-user"]);
    expect(visible.exitCode, visible.stderr).toBe(0);
    expect(visible.stdout.trim()).toBe("member-user member-lib");
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "BC-4: a bin reaches a workspace member through another member's package (T123)",
  async () => {
    // chain-cli -> member chain-w1 -> registry chain-helper -> member chain-w2.
    project("conformance_member_chain");
    // The earlier tests' member-lib would be a workspace member of this project too.
    rmSync(join(inner.dir, "packages"), { recursive: true, force: true });
    for (const member of ["chain-w1", "chain-w2"]) {
      for (const file of ["package.json", "index.js"]) {
        inner.write(`packages/${member}/${file}`, fixture(`conformance_member_chain/packages/${member}/${file}`));
      }
    }
    inner.write(
      "packages/chain-w1/BUILD.bazel",
      'load("@npm//:defs.bzl", "npm_link_all_packages")\nload("@rules_bun//bun:defs.bzl", "bun_library")\n\nnpm_link_all_packages()\n\nbun_library(\n    name = "pkg",\n    srcs = ["index.js"],\n    data = ["package.json"],\n    visibility = ["//visibility:public"],\n    deps = [":node_modules/chain-helper"],\n)\n',
    );
    inner.write(
      "packages/chain-w2/BUILD.bazel",
      'load("@rules_bun//bun:defs.bzl", "bun_library")\n\nbun_library(\n    name = "pkg",\n    srcs = ["index.js"],\n    data = ["package.json"],\n    visibility = ["//visibility:public"],\n)\n',
    );
    const result = await inner.run(["run", "//:node_modules/chain-cli/bin/chain-cli"]);
    console.log(errorLine(result.stderr));
    expect(result.exitCode, result.stderr).toBe(0);
    expect(result.stdout.trim()).toBe("chain-cli chain-w1 chain-helper chain-w2");
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "BC-4: a bin reaches a workspace member through a member's workspace: link and two further members (T131)",
  async () => {
    // chain-cli -> member chain-w1 -workspace:-> member chain-mid -> registry chain-helper -> member chain-w2.
    project("conformance_member_workspace_chain");
    // The earlier tests' members would be workspace members of this project too.
    rmSync(join(inner.dir, "packages"), { recursive: true, force: true });
    for (const member of ["chain-w1", "chain-mid", "chain-w2"]) {
      for (const file of ["package.json", "index.js"]) {
        inner.write(`packages/${member}/${file}`, fixture(`conformance_member_workspace_chain/packages/${member}/${file}`));
      }
    }
    const library = (deps: string) =>
      `load("@npm//:defs.bzl", "npm_link_all_packages")\nload("@rules_bun//bun:defs.bzl", "bun_library")\n\nnpm_link_all_packages()\n\nbun_library(\n    name = "pkg",\n    srcs = ["index.js"],\n    data = ["package.json"],\n    visibility = ["//visibility:public"],\n    deps = [${deps}],\n)\n`;
    // chain-w1 links chain-mid's target through its `workspace:` dependency.
    inner.write("packages/chain-w1/BUILD.bazel", library('":node_modules/chain-mid"'));
    inner.write("packages/chain-mid/BUILD.bazel", library('":node_modules/chain-helper"'));
    inner.write(
      "packages/chain-w2/BUILD.bazel",
      'load("@rules_bun//bun:defs.bzl", "bun_library")\n\nbun_library(\n    name = "pkg",\n    srcs = ["index.js"],\n    data = ["package.json"],\n    visibility = ["//visibility:public"],\n)\n',
    );
    // The T123 test's build left chain-w1's link to chain-helper in the output tree, which the
    // launcher refuses as an earlier build's link until `bazel clean` (feature 003 T122).
    const clean = await inner.run(["clean"]);
    expect(clean.exitCode, clean.stderr).toBe(0);
    const result = await inner.run(["run", "//:node_modules/chain-cli/bin/chain-cli"]);
    console.log(errorLine(result.stderr));
    expect(result.exitCode, result.stderr).toBe(0);
    expect(result.stdout.trim()).toBe("chain-cli chain-w1 chain-mid chain-helper chain-w2");
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "BC-4, BC-12: a bin needs a member only where the optional package linking it is installed (T181)",
  async () => {
    // mplat-cli -optional-> registry mplat-helper (os linux) -> member mplat-w, whose target is
    // for Linux only, as a member a Linux-only package links can be.
    project("conformance_member_platform");
    // The earlier tests' members would be workspace members of this project too.
    rmSync(join(inner.dir, "packages"), { recursive: true, force: true });
    for (const file of ["package.json", "index.js"]) {
      inner.write(`packages/mplat-w/${file}`, fixture(`conformance_member_platform/packages/mplat-w/${file}`));
    }
    inner.write(
      "packages/mplat-w/BUILD.bazel",
      'load("@rules_bun//bun:defs.bzl", "bun_library")\n\nbun_library(\n    name = "pkg",\n    srcs = ["index.js"],\n    data = ["package.json"],\n    target_compatible_with = ["@platforms//os:linux"],\n    visibility = ["//visibility:public"],\n)\n',
    );
    const bin = "//:node_modules/mplat-cli/bin/mplat-cli";
    const members = async (platform: string) => {
      const result = await inner.run(["cquery", `--platforms=//:${platform}`, `labels(members, ${bin})`]);
      expect(result.exitCode, result.stderr).toBe(0);
      return result.stdout;
    };

    // On macOS mplat-helper is not installed, so the bin declares no mplat-w and stays buildable.
    const darwin = await inner.run(["build", "--nobuild", "--platforms=//:darwin_arm64", bin]);
    console.log(darwin.stderr.split("\n").filter((l) => /ERROR|incompatible/.test(l)).join("\n"));
    expect(darwin.exitCode, darwin.stderr).toBe(0);
    expect(await members("darwin_arm64")).not.toContain("//packages/mplat-w:pkg");

    // On Linux it is, and the bin declares mplat-w.
    const linux = await inner.run(["build", "--nobuild", "--platforms=//:linux_x64", bin]);
    expect(linux.exitCode, linux.stderr).toBe(0);
    expect(await members("linux_x64")).toContain("//packages/mplat-w:pkg");

    // On the host the bin runs, with mplat-helper and mplat-w on Linux only. The earlier tests'
    // builds left links in the output tree, which the launcher refuses until `bazel clean`.
    const clean = await inner.run(["clean"]);
    expect(clean.exitCode, clean.stderr).toBe(0);
    const result = await inner.run(["run", bin]);
    console.log(errorLine(result.stderr));
    expect(result.exitCode, result.stderr).toBe(0);
    expect(result.stdout.trim()).toBe(process.platform === "linux" ? "mplat-cli mplat-helper mplat-w" : "mplat-cli none");
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

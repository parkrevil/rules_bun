// Canary C-LIBC (feature 004 research R11, FR-012): Bun 1.4.4 writes a package's
// `libc` beside `os` and `cpu` as the one C library it allows, a string: a
// package published for one libc gets that libc, one published as `!musl` gets
// "glibc", and one published for both gets no `libc`. The reader takes `libc` as
// it takes `os` and `cpu` (a string or a list, `!` values included).

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const READER = "the libc of an entry in bun/private/lockfile.bzl";

// Published libc of the three packages; the musl package's comes from its archive.
function publish(name: string, doc: Record<string, any>, negatedMusl: string[]) {
  if (name === "native-linux-x64") doc.versions["1.0.0"].libc = ["glibc", "musl"];
  if (name === "native-linux-arm64") doc.versions["1.0.0"].libc = negatedMusl;
  return doc;
}

test("libc forms", async () => {
  const { lock } = await runInstall(
    {
      "package.json": manifest({
        name: "c-libc",
        optionalDependencies: { "native-linux-x64": "1.0.0", "native-linux-x64-musl": "1.0.0", "native-linux-arm64": "1.0.0" },
      }),
    },
    {
      lockfileOnly: true,
      registry: { packument: (name, doc) => publish(name, doc, ["!musl"]) },
      // Red: the negated package is published for both C libraries instead.
      alter: red({ packument: (name, doc) => publish(name, doc, ["glibc", "musl"]) }),
    },
  );
  const one = lock.packages["native-linux-x64-musl"]?.[2];
  const both = lock.packages["native-linux-x64"]?.[2];
  const negated = lock.packages["native-linux-arm64"]?.[2];
  if (one?.libc !== "musl") canaryFail("C-LIBC", "info libc (one value)", READER, LOCKFILE_SOURCE, one);
  if (both === undefined || "libc" in both) canaryFail("C-LIBC", "info libc (every libc)", READER, LOCKFILE_SOURCE, both);
  if (negated?.libc !== "glibc") canaryFail("C-LIBC", "info libc (a ! value)", READER, LOCKFILE_SOURCE, negated);
});

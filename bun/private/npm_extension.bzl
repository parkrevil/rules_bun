"""Implementation of the `npm` module extension (FR-005, FR-008, FR-009, research R3)."""

load(":lockfile.bzl", "DEPENDENCY_KINDS", "read_lockfile")
load(":npm_names.bzl", "bin_targets", "target_name")
load(":npm_repositories.bzl", "npm_hub_repository", "npm_package_repository")
load(":npmrc.bzl", "has_userinfo", "package_url", "read_npmrc")
load(":resolve.bzl", "resolve")
load(":workspaces.bzl", "compare_manifests", "match_members", "workspace_patterns")

translate_lock = tag_class(
    doc = """Creates the hub repository `@<name>` with the packages of one `bun.lock`.

Evaluation fails with an English error naming the file and the remedy when the label names
`bun.lockb`, when `lockfileVersion` is not 1, 2 or 3, when the file is not JSONC, when the root or
a member `package.json` and the lockfile differ in dependencies, workspace members, catalogs or
overrides ("run `bun install` and commit bun.lock"), when two entries of one `name@version` record
different URLs or integrities, when the root `package.json` uses an override form rules_bun
does not compare, and when a URL in `bun.lock` (an entry's URL or resolution, a dependency
specifier) or in a `package.json` holds user information, as a registry URL of `npmrc` does: the
error names the file and the entry or dependency, never the URL, since credentials come only from
Bazel's downloader (`--credential_helper`, `.netrc`). Overrides are compared as Bun reads them: `overrides` when present, else
`resolutions`.""",
    attrs = {
        "name": attr.string(
            doc = "Name of the hub repository, which `use_repo` brings into scope. Two `translate_lock` tags, in one module or in several, that use one name fail evaluation naming each module and the name.",
            default = "npm",
        ),
        "bun_lock": attr.label(
            doc = "The `bun.lock` file, written by Bun as a text lockfile. The root `package.json` is the `package.json` next to it, and the workspace members are the directories its `workspaces` patterns match.",
            mandatory = True,
        ),
        "npmrc": attr.label(
            doc = "An `.npmrc` file whose `registry` and `@<scope>:registry` keys name the registries of packages whose lockfile URL is empty. Other keys, credentials included, are not read; a registry URL holding user information (`https://user:token@host/`) fails evaluation with an error naming the key, without the credential.",
        ),
        "workspace_target_name": attr.string(
            doc = "Name of the target in each workspace member's package that a `workspace:` dependency links to. The target must provide `BunLibraryInfo`, such as a `bun_library`, and should carry the member's `package.json` in `data`.",
            default = "pkg",
        ),
        "exclude_package_contents": attr.string_list_dict(
            doc = "Package name, or `*` for every package, to Bazel `glob` exclude patterns relative to the package root, for files left out of the package (both lists apply to a package that has its own). Patterns match the file names the archive holds, including files rules_bun renames because Bazel cannot address their names; for those, rules_bun matches the `*` and `**` wildcards as `glob` documents them.",
        ),
    },
)

replace_package = tag_class(
    doc = """Replaces the download of one package with a package archive in the workspace.

Root module only: a use in another module fails evaluation naming the module, and a package
replaced twice fails evaluation naming both archives. The replacement applies to every lockfile
that lists the package, the root module's and those of the modules it depends on. A build that
needs the package fails when the archive's digest differs from the integrity the lockfile records,
naming the package, the archive and both values, and no program or test that carries the package
runs before that check passes.""",
    attrs = {
        "package": attr.string(
            doc = "The package as `name@version`, as slot 0 of its `bun.lock` entry writes it.",
            mandatory = True,
        ),
        "replacement": attr.label(
            doc = "A `.tgz` package archive; its digest must equal the integrity the lockfile records.",
            mandatory = True,
            allow_single_file = True,
        ),
    },
)

def _sanitize(text):
    return "".join([c if c.isalnum() or c in ".-" else "_" for c in text.elems()])

_DIGEST_BYTES = {"sha256": 32, "sha384": 48, "sha512": 64}

def padded_integrity(integrity):
    """An integrity with its base64 padded to the digest's length, as Bazel's downloader reads it.

    Bun 1.4.4 writes every integrity as the digest's unpadded base64 followed by `==` (canary
    C-INTEGRITY), which is invalid base64 for a `sha256` or `sha384` digest; the digest is kept.

    Args:
        integrity: The integrity as `bun.lock` records it.

    Returns:
        The same integrity with correct padding; an unknown algorithm is returned unchanged.
    """
    algorithm, _, digest = integrity.partition("-")
    size = _DIGEST_BYTES.get(algorithm)
    if size == None:
        return integrity
    base64 = digest.rstrip("=")
    return "{}-{}{}".format(algorithm, base64, "=" * ((size + 2) // 3 * 4 - len(base64)))

def _label_text(label):
    """A label as a root-module tag writes it: `//pkg:name`, or with its canonical repository."""
    text = "//{}:{}".format(label.package, label.name)

    # Diagnostic text only, never resolved as a label. bazel.build documents no API that returns a
    # label's apparent-name display form as a string (only print() and fail() render it), so this
    # spells out the canonical form `@@repo//pkg:name`.
    # buildifier: disable=canonical-repository
    return text if label.repo_name == "" else "@@{}{}".format(label.repo_name, text)

def _package_repo_names(hub, name_versions):
    """`name@version` -> package repository name, `__<n>` added in sorted order on a clash."""
    by_name = {}
    for name_version in sorted(name_versions):
        name, version = name_versions[name_version]
        by_name.setdefault("{}__{}__{}".format(hub, _sanitize(name), _sanitize(version)), []).append(name_version)
    names = {}
    for repo, group in by_name.items():
        for n, name_version in enumerate(group):
            names[name_version] = repo if len(group) == 1 else "{}__{}".format(repo, n)
    return names

_REMEDY = "run `bun install` and commit bun.lock"

_LOCKB_REMEDY = ("run `bun install --save-text-lockfile --frozen-lockfile --lockfile-only` " +
                 "(bun.com pm/lockfile), delete bun.lockb and pass bun.lock as bun_lock")

_USERINFO_REMEDY = "give credentials through Bazel's downloader (--credential_helper or .netrc) instead"

# Bounds the walk of nested dependency maps; Starlark has no unbounded loop.
_MAX_MAPS = 1 << 20

def _url_with_userinfo(text):
    """Whether a specifier or resolution is a URL whose authority holds user information."""
    return type(text) == "string" and "://" in text and has_userinfo(text)

def _check_lockfile_urls(file, lockfile):
    """Fails naming the first entry whose URL holds user information (FR-002, research R2).

    The URL is slot 1 of an npm entry and the resolution of slot 0 of any other entry. Neither the
    URL nor slot 0 is printed; the key is a package path.
    """
    for key in sorted(lockfile.entries.keys()):
        entry = lockfile.entries[key]
        url = entry.url if entry.kind == "npm" else entry.resolution
        if (entry.kind == "npm" and has_userinfo(url)) or _url_with_userinfo(url):
            fail('rules_bun: {}: the packages entry "{}" records a URL that holds user information (credentials before an @); {}'.format(file, key, _USERINFO_REMEDY))

def _check_specs(file, maps):
    """Fails naming the first dependency whose specifier is a URL holding user information (FR-002).

    Args:
        file: The file the maps come from, for the error.
        maps: Dependency name -> specifier maps; a value that is itself a map (nested overrides,
            named catalogs) is walked too.
    """
    work = [m for m in maps if type(m) == "dict"]
    for _ in range(_MAX_MAPS):
        if not work:
            return
        current = work.pop(0)
        for name in sorted(current.keys()):
            value = current[name]
            if type(value) == "dict":
                work.append(value)
            elif _url_with_userinfo(value):
                fail('rules_bun: {}: the dependency "{}" is a URL that holds user information (credentials before an @); {}'.format(file, name, _USERINFO_REMEDY))
    fail("rules_bun: {} nests more than {} dependency maps".format(file, _MAX_MAPS))

def _read_json(module_ctx, path, file):
    if not path.exists:
        fail("rules_bun: {} does not exist; the npm extension reads the package.json next to bun.lock and in each workspace member".format(file))
    text = module_ctx.read(path)
    if not text.strip():
        fail("rules_bun: {} is empty".format(file))
    return json.decode(text)

def _descend(path, relative):
    for part in relative.split("/") if relative else []:
        path = path.get_child(part)
    return path

def _members(module_ctx, tag, root_file, root_manifest, lockfile):
    """Fails unless the members the root `workspaces` patterns match are the lockfile's (R9)."""
    lock_dir = module_ctx.path(tag.bun_lock).dirname

    def list_dir(relative):
        path = _descend(lock_dir, relative)
        if not path.exists or not path.is_dir:
            return []
        return sorted([c.basename for c in path.readdir(watch = "auto") if c.is_dir])

    def has_manifest(relative):
        manifest = _descend(lock_dir, relative).get_child("package.json")
        module_ctx.watch(manifest)
        return manifest.exists

    matched = match_members(workspace_patterns(root_manifest), list_dir, has_manifest, root_file)
    if matched.error:
        fail("rules_bun: " + matched.error)
    recorded = sorted([p for p in lockfile.workspaces.keys() if p])
    for member in matched.value:
        if member not in recorded:
            fail('rules_bun: {}: the workspace member "{}", which "workspaces" matches, is not in bun.lock; {}'.format(root_file, member, _REMEDY))
    for member in recorded:
        if member not in matched.value:
            fail('rules_bun: {}: bun.lock records the workspace member "{}", which "workspaces" does not match; {}'.format(root_file, member, _REMEDY))

def _manifests(module_ctx, tag, lockfile):
    """Member path -> `struct(file, value)` of the root and member `package.json` files."""
    lock_dir = module_ctx.path(tag.bun_lock).dirname
    manifests = {}
    for path in sorted(lockfile.workspaces.keys()):
        manifest = _descend(lock_dir, path)
        package = "/".join([p for p in [tag.bun_lock.package, path] if p])

        # Diagnostic text only, as in `_label_text`.
        # buildifier: disable=canonical-repository
        file = "{}//{}:package.json".format("@@" + tag.bun_lock.repo_name if tag.bun_lock.repo_name else "", package)
        manifests[path] = struct(file = file, value = _read_json(module_ctx, manifest.get_child("package.json"), file))
    return manifests

def _translate(module_ctx, tag, replacements):
    file = str(tag.bun_lock)
    if tag.bun_lock.name.endswith(".lockb"):
        fail("rules_bun: {} is Bun's binary lockfile, which rules_bun does not read; {}".format(file, _LOCKB_REMEDY))
    path = module_ctx.path(tag.bun_lock)
    if not path.exists and path.dirname.get_child(tag.bun_lock.name + "b").exists:
        fail("rules_bun: {} does not exist, only Bun's binary lockfile bun.lockb, which rules_bun does not read; {}".format(file, _LOCKB_REMEDY))
    lockfile = read_lockfile(module_ctx.read(tag.bun_lock), file)
    if lockfile.error:
        fail(lockfile.error)

    # Before any check that prints a URL or a specifier (research R2).
    _check_lockfile_urls(file, lockfile.value)
    _check_specs(file, [getattr(w, kind) for w in lockfile.value.workspaces.values() for kind in DEPENDENCY_KINDS] + [
        lockfile.value.overrides,
        lockfile.value.catalog,
        lockfile.value.catalogs,
    ])
    npmrc = None
    if tag.npmrc:
        npmrc = read_npmrc(module_ctx.read(tag.npmrc), str(tag.npmrc))
        if npmrc.error:
            fail("rules_bun: " + npmrc.error)
        npmrc = npmrc.value
    manifests = _manifests(module_ctx, tag, lockfile.value)
    for path in sorted(manifests.keys()):
        value = manifests[path].value
        _check_specs(manifests[path].file, [value.get(kind) for kind in DEPENDENCY_KINDS + ["overrides", "resolutions", "catalog", "catalogs"]] + [
            value.get("workspaces"),
        ])
    _members(module_ctx, tag, manifests[""].file, manifests[""].value, lockfile.value)
    comparison = compare_manifests(lockfile.value, manifests)
    if comparison.error:
        fail("rules_bun: " + comparison.error)
    resolution = resolve(lockfile.value, file)
    if resolution.error:
        fail(resolution.error)
    entries = lockfile.value.entries

    # One package repository serves every entry of a name@version (research R3), so all entries
    # of one must agree on the download, including an entry rules_bun does not fetch: whichever
    # of them a dependency reaches must not decide which archive is verified.
    first_entries = {}
    for key in sorted(entries.keys()):
        entry = entries[key]
        if entry.kind != "npm":
            continue
        name_version = "{}@{}".format(entry.name, entry.version)
        first = first_entries.setdefault(name_version, entry)
        for field, what in [("integrity", "integrity"), ("url", "URL")]:
            if getattr(first, field) != getattr(entry, field):
                fail('rules_bun: {}: the entries "{}" and "{}" of {} record different {} values, "{}" and "{}"; run `bun install` to rewrite bun.lock'.format(
                    file,
                    first.key,
                    entry.key,
                    name_version,
                    what,
                    getattr(first, field),
                    getattr(entry, field),
                ))

    packages = {}
    for instance in resolution.value.instances.values():
        if instance.status != "ok":
            continue
        entry = entries[instance.key]
        packages.setdefault("{}@{}".format(entry.name, entry.version), entry)
    repo_names = _package_repo_names(tag.name, {nv: (e.name, e.version) for nv, e in packages.items()})

    # The content identity of each package version (research R1): what its download or
    # replacement check verifies, and which of its files are carried.
    identities = {}
    for name_version, entry in packages.items():
        exclude = tag.exclude_package_contents.get("*", []) + tag.exclude_package_contents.get(entry.name, [])
        identities[name_version] = struct(
            integrity = padded_integrity(entry.integrity),
            source = _label_text(replacements[name_version]) if name_version in replacements else package_url(npmrc, entry.name, entry.version, entry.url),
            exclude = sorted({p: None for p in exclude}.keys()),
        )

    for name_version, repo in repo_names.items():
        entry = packages[name_version]
        npm_package_repository(
            name = repo,
            url = package_url(npmrc, entry.name, entry.version, entry.url),
            integrity = identities[name_version].integrity,
            exclude = tag.exclude_package_contents.get("*", []) + tag.exclude_package_contents.get(entry.name, []),
            package = entry.name,
            version = entry.version,
            bins = sorted(entry.bin.values()),
            replacement = replacements.get(name_version),
            replacement_label = _label_text(replacements[name_version]) if name_version in replacements else "",
        )

    instances = {}
    for instance in resolution.value.instances.values():
        name_version = "{}@{}".format(instance.name, instance.version)
        if instance.status != "ok":
            instances[instance.id] = {"package": name_version, "status": instance.status}
            continue
        instances[instance.id] = {
            "dependency_keys": instance.dependency_keys,
            "edges": instance.edges,
            "exclude": identities[name_version].exclude,
            "integrity": identities[name_version].integrity,
            "peers": instance.peers,
            "package": instance.name,
            "replaced": name_version in replacements,
            "repo": repo_names[name_version],
            "source": identities[name_version].source,
            "status": "ok",
            "store_name": instance.store_name,
        }
    lock_dir = tag.bun_lock.package
    links = {}
    for path, aliases in resolution.value.links.items():
        package = "/".join([p for p in [lock_dir, path] if p])
        targets = {}
        for alias, link in aliases.items():
            root = resolution.value.instances[link.root]
            entry_bins = entries[root.key].bin if root.status == "ok" else {}
            bins = bin_targets("{}@{}".format(root.name, root.version), entry_bins)
            if bins.error:
                fail("rules_bun: {}: {}".format(file, bins.error))
            originals = {target_name(b): b for b in entry_bins}
            targets[alias] = {
                "bins": {name: [bin_path, originals[name]] for name, bin_path in bins.value.items()},
                "closure": link.closure,
                "optional": link.optional,
                "root": link.root,
            }

        # A `workspace:` dependency links to the member's target (research R7).
        for alias, member in resolution.value.members[path].items():
            targets[alias] = {"workspace": "//{}:{}".format(
                "/".join([p for p in [lock_dir, member] if p]),
                tag.workspace_target_name,
            )}
        names = {}
        for alias in sorted(targets.keys()):
            name = target_name(alias)
            if name in names:
                fail('rules_bun: {}: the packages "{}" and "{}" of the workspace "{}" both become the target name "node_modules/{}"'.format(file, names[name], alias, path, name))
            names[name] = alias
            targets[alias]["target"] = name
        links[package] = targets
    npm_hub_repository(
        name = tag.name,
        lockfile = file,
        instances = json.encode(instances),
        links = json.encode(links),
    )

_LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

_REPOSITORY_CHARACTERS = _LETTERS + "0123456789_-."

def _valid_repository_name(name):
    """Whether `name` is an apparent repository name (bazel.build concepts/labels)."""
    return bool(name) and name[0] in _LETTERS and all([c in _REPOSITORY_CHARACTERS for c in name.elems()])

def _valid_target_name(name):
    """Whether `name` is a target name (bazel.build concepts/labels): characters, `/` segments."""
    if not name or target_name(name) != name:
        return False
    return all([segment not in ("", ".", "..") for segment in name.split("/")])

def _validate_translate_lock(who, tag):
    """Fails naming the module, the tag and the value of an invalid name (FR-016, research R8)."""
    for attribute, value, kind, valid in [
        ("name", tag.name, "repository", _valid_repository_name(tag.name)),
        ("workspace_target_name", tag.workspace_target_name, "target", _valid_target_name(tag.workspace_target_name)),
    ]:
        if not valid:
            fail('rules_bun: {}: npm.translate_lock: {} "{}" is not a valid {} name'.format(who, attribute, value, kind))

def _npm_extension_impl(module_ctx):
    replacements = {}
    for mod in module_ctx.modules:
        for tag in mod.tags.replace_package:
            if not mod.is_root:
                fail("npm.replace_package is for the root module only; the module {}@{} uses it for {}".format(
                    mod.name,
                    mod.version,
                    tag.package,
                ))
            if tag.package in replacements:
                fail("npm.replace_package replaces {} twice: with {} and with {}".format(
                    tag.package,
                    _label_text(replacements[tag.package]),
                    _label_text(tag.replacement),
                ))
            replacements[tag.package] = tag.replacement

    # Hub names are not deconflicted, as rules_js does not deconflict them (FR-032).
    hubs = {}
    for mod in module_ctx.modules:
        for tag in mod.tags.translate_lock:
            who = "the root module" if mod.is_root else "the module {}@{}".format(mod.name, mod.version)
            _validate_translate_lock(who, tag)
            hubs.setdefault(tag.name, []).append("{} for {}".format(who, _label_text(tag.bun_lock)))
    for name in sorted(hubs.keys()):
        if len(hubs[name]) > 1:
            fail('npm.translate_lock asks for the hub name "{}" more than once: {}; give each bun.lock its own name'.format(
                name,
                ", ".join(hubs[name]),
            ))
    for mod in module_ctx.modules:
        for tag in mod.tags.translate_lock:
            _translate(module_ctx, tag, replacements)
    return module_ctx.extension_metadata(reproducible = True)

_NPM_DOC = """Creates hub repositories with the npm packages that `bun.lock` files list.

    npm = use_extension("@rules_bun//bun:extensions.bzl", "npm")
    npm.translate_lock(bun_lock = "//:bun.lock")
    use_repo(npm, "npm")

In the `BUILD` file of the lockfile's package and of each workspace member, call the hub's macro
once; elsewhere it fails, naming the packages where it may be called:

    load("@npm//:defs.bzl", "npm_link_all_packages")

    npm_link_all_packages()

Generated targets (public API, under these naming rules):

- `:node_modules/<package>` for each package that workspace package declares in `dependencies`,
  `devDependencies`, `optionalDependencies` or `peerDependencies`, scope kept
  (`:node_modules/@scope/name`); accepted in `deps` of `bun_library`, `bun_binary` and `bun_test`,
  at the version the lockfile lists for that workspace package. A `workspace:` dependency links to
  the member's target named by `workspace_target_name`.
- `:node_modules/<package>/bin/<bin>` for each `bin` entry of such a package (a string `bin` is
  named after the package name without its scope); it runs with `bazel run` or as a build action's
  tool, with the toolchain's Bun. A bin runs when its file has a source extension or its first line
  is a `#!` line naming `node` or `bun` (npm's bin convention, `#!/usr/bin/env node`; canary C18
  pins that Bun runs such a file); any other bin, such as a shell script or a native executable,
  fails its analysis naming the reason. Every bin target is `manual`, so `bazel build //...`
  builds none; a bin a target uses or the command line names is built. The bins of a declared
  optional package with `os`, `cpu` or `libc` are compatible only with the platforms it matches.
  Executables declared only through `directories.bin` get no target.
- Every character of `<package>` or `<bin>` outside Bazel's target-name set is written `_`; two
  names that become one fail evaluation naming both.

Repositories named `<name>__...` and other targets of the hub are not public API.

Packages: an optional dependency whose entry has `os` or `cpu` is carried only on target platforms
that match (`select()` on `@platforms`, `!` negations included); a value with no `@platforms`
constraint, such as `sunos` or `ppc64`, matches no platform. An entry's `libc` (`glibc` or `musl`,
which Bun 1.4.4 writes) is matched against the target platform's
`@rules_bun//bun/platforms/libc:libc` constraint, by npm's rule: on a Linux platform with
`@rules_bun//bun/platforms/libc:glibc` or `:musl`, only the entries whose `libc` allows that C
library are carried; on a Linux platform without the constraint (its default,
`:unconstrained`), every `libc` variant is carried, because the platform does not say which C
library it has; an entry with `libc` matches no other OS. To get only one variant, add the C
library to the Linux platform: `constraint_values = ["@platforms//os:linux",
"@platforms//cpu:x86_64", "@rules_bun//bun/platforms/libc:glibc"]`. A non-optional dependency is
carried whatever its `os`, `cpu` and `libc` say. An entry rules_bun does not fetch (`file:`, a tarball URL, `git+` or `github:`
and any other resolution, a patched package, an entry without integrity, an integrity algorithm
other than `sha256`, `sha384` and `sha512`) gets no download; a target that needs it fails analysis
naming the package and the reason, and other targets are unaffected. A link that reaches such an
entry, on any platform, is tagged `manual`, so `bazel build //...` skips it. An archive's files keep their
names, `BUILD` files and names outside the target-name set included. An empty directory of an
archive is not carried. Archives holding symbolic links are not covered by a test (unverified).

Fetching: only the packages a requested target needs are downloaded, by Bazel's downloader, and
verified against the lockfile's integrity. The URL is the one the lockfile records, or, for an
empty one, `<registry>/<name>/-/<basename>-<version>.tgz` with the registry from `npmrc`, else
`https://registry.npmjs.org`. A `--downloader_config` rewrite redirects a download to a mirror
without changing the integrity check. Credentials come only from Bazel: `--credential_helper` and
the user's `.netrc`; no credential enters a repository attribute or a generated file. A URL holding
user information (`https://user:token@host/`) fails evaluation naming the file and the entry or
dependency, without the URL, whether `bun.lock` (an entry's URL or resolution, a dependency
specifier), a `package.json` or the `.npmrc` records it. The
extension is reproducible and not OS- or architecture-dependent, so it adds no entry to
`MODULE.bazel.lock`.

Several lockfiles: each `translate_lock` tag creates its own hub, in the root module and in any
other module, so a module can use npm packages of its own lockfile. A target that depends on
packages of several hubs carries one instance of each package version: instances from different
lockfiles are carried once only when both lockfiles describe the same content (equal integrity,
source, that is the download URL or the `replace_package` archive, and exclusion policy) and their
dependencies resolve to the same versions. Any other two fail analysis, naming the package
version, both hubs with their lockfiles and the first property that differs with both values, or
else the dependency whose versions differ.

Platforms: the tests of this extension and of the packages it creates ran on Linux (WSL) only;
macOS and Windows are unverified until CI runs them. Evaluation of a 2,000-package lockfile took
under 1 s there.
"""

npm = module_extension(
    implementation = _npm_extension_impl,
    doc = _NPM_DOC,
    tag_classes = {
        "replace_package": replace_package,
        "translate_lock": translate_lock,
    },
    os_dependent = False,
    arch_dependent = False,
)

"""The files of a project the conformance test copies for the oracle (feature 006 research R6)."""

def conformance_files(name = "conformance_files"):
    """Every file of this package and, through theirs, of its subpackages.

    Args:
        name: The filegroup's name.
    """
    native.filegroup(
        name = name,
        srcs = native.glob(["**"]) + [
            "//{}/{}:{}".format(native.package_name(), subpackage, name)
            for subpackage in native.subpackages(include = ["**"], allow_empty = True)
        ],
        visibility = ["//bun/tests/npm:__subpackages__"],
    )

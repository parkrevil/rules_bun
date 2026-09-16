#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

TAG=$1
PREFIX="rules_bun-${TAG:1}"
ARCHIVE="rules_bun-$TAG.tar.gz"

git archive --format=tar --prefix="${PREFIX}"/ "${TAG}" | gzip > "$ARCHIVE"

docs="$(mktemp -d)"
targets="$(mktemp)"
bazel --output_base="$docs" query --output=label --output_file="$targets" 'kind("starlark_doc_extract rule", //...)'
bazel --output_base="$docs" build --target_pattern_file="$targets"
tar --create --auto-compress \
    --directory "$(bazel --output_base="$docs" info bazel-bin)" \
    --file "$GITHUB_WORKSPACE/${ARCHIVE%.tar.gz}.docs.tar.gz" .

cat << EOF
## Bzlmod

Add to your \`MODULE.bazel\` file:

\`\`\`starlark
bazel_dep(name = "rules_bun", version = "${TAG:1}")
\`\`\`
EOF

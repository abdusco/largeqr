#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
ARCH="${ARCH:-arm64}"
VERSION="${VERSION:-dev}"
VERSION_CLEAN="${VERSION#v}"

case "$ARCH" in
  arm64|x86_64) ;;
  *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac
if [[ ! "$VERSION_CLEAN" =~ ^[a-zA-Z0-9._+-]+$ ]]; then
  echo "VERSION must contain only letters, digits, dots, underscores, plus signs, or dashes." >&2
  exit 1
fi

build_dir=$(mktemp -d "${TMPDIR:-/tmp}/largeqr-build.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
sed "s/^let version = \"dev\"/let version = \"$VERSION_CLEAN\"/" LargeQR.swift > "$build_dir/main.swift"

echo "Building largeqr for $ARCH, version $VERSION_CLEAN"
swiftc -O -target "${ARCH}-apple-macosx11.0" \
  -module-cache-path "$build_dir/module-cache" \
  -framework Cocoa -framework CoreImage -framework Foundation \
  "$build_dir/main.swift" -o "largeqr-${ARCH}"
echo "Built largeqr-${ARCH}"
